import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'dart:convert';
import 'firebase_options.dart';
import 'config.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const FusionApp());
}

// ── USER MODEL ─────────────────────────────────────────────────────────────
class DiscordUser {
  final String id;
  final String username;
  final String? avatar;
  final String nickname;
  final List<String> roles;
  final String accessToken;

  DiscordUser({
    required this.id,
    required this.username,
    this.avatar,
    required this.nickname,
    required this.roles,
    required this.accessToken,
  });

  factory DiscordUser.fromJson(Map<String, dynamic> json) {
    return DiscordUser(
      id: json['id'],
      username: json['username'],
      avatar: json['avatar'],
      nickname: json['nickname'] ?? json['username'],
      roles: List<String>.from(json['roles'] ?? []),
      accessToken: json['accessToken'],
    );
  }
}

// ── APP ────────────────────────────────────────────────────────────────────
class FusionApp extends StatelessWidget {
  const FusionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fusion Esports',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
      ),
      home: const AuthWrapper(),
    );
  }
}

// ── AUTH WRAPPER ───────────────────────────────────────────────────────────
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  DiscordUser? _user;
  bool _isLoading = false;
  late AppLinks _appLinks;
  StreamSubscription? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  void _initDeepLinks() {
    _appLinks = AppLinks();
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == 'fusionesports' && uri.host == 'auth') {
        final code = uri.queryParameters['code'];
        if (code != null) _handleDiscordCallback(code);
      }
    });
  }

  Future<void> _handleDiscordCallback(String code) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('https://fusion-esports.netlify.app/api/discord_auth?code=$code'),
      );
      if (response.statusCode == 200) {
        final user = DiscordUser.fromJson(jsonDecode(response.body));
        setState(() => _user = user);
      } else {
        _showError('Login failed. Please try again.');
      }
    } catch (e) {
      _showError('Something went wrong. Please try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _loginWithDiscord() async {
    const clientId = '1473722302968631588';
    const redirectUri = 'https://fusion-esports.netlify.app/auth/callback';
    const scope = 'identify guilds.members.read';
    final url = Uri.parse(
      'https://discord.com/oauth2/authorize?client_id=$clientId&redirect_uri=${Uri.encodeComponent(redirectUri)}&response_type=code&scope=${Uri.encodeComponent(scope)}',
    );
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void _logout() => setState(() => _user = null);

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF6C63FF)),
              SizedBox(height: 16),
              Text('Logging you in...', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      );
    }

    if (_user == null) {
      return LoginPage(onLogin: _loginWithDiscord);
    }

    return MainPage(user: _user!, onLogout: _logout);
  }
}

// ── LOGIN PAGE ─────────────────────────────────────────────────────────────
class LoginPage extends StatelessWidget {
  final VoidCallback onLogin;

  const LoginPage({super.key, required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1A1A2E), Color(0xFF0A0A0F)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                // Logo
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C63FF).withOpacity(0.4),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset('assets/icon.png'),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Fusion Esports',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your community hub',
                  style: TextStyle(color: Colors.white54, fontSize: 16),
                ),
                const Spacer(),
                // Login button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: onLogin,
                    icon: const Icon(Icons.discord, size: 24),
                    label: const Text(
                      'Login with Discord',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5865F2),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'By logging in you agree to our terms of service',
                  style: TextStyle(color: Colors.white24, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── MAIN PAGE ──────────────────────────────────────────────────────────────
class MainPage extends StatefulWidget {
  final DiscordUser user;
  final VoidCallback onLogout;

  const MainPage({super.key, required this.user, required this.onLogout});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(user: widget.user),
      const SchedulePage(),
      const StatsPage(),
      const NewsPage(),
    ];

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF12121A),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Schedule'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Stats'),
          NavigationDestination(icon: Icon(Icons.newspaper), label: 'News'),
        ],
      ),
    );
  }
}

// ── DATA FETCHING ──────────────────────────────────────────────────────────
Future<Map<String, dynamic>> fetchBinData() async {
  final response = await http.get(
    Uri.parse('https://api.jsonbin.io/v3/b/${Config.jsonBinId}/latest'),
    headers: {'X-Master-Key': Config.jsonBinApiKey},
  );
  if (response.statusCode == 200) {
    return jsonDecode(response.body)['record'];
  }
  throw Exception('Failed to load data');
}

// ── HOME PAGE ──────────────────────────────────────────────────────────────
class HomePage extends StatefulWidget {
  final DiscordUser user;

  const HomePage({super.key, required this.user});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<Map<String, dynamic>> _data;

  @override
  void initState() {
    super.initState();
    _data = fetchBinData();
  }

  String _getNextTournament(Map<String, dynamic> tournament) {
    final now = DateTime.now();
    final dayOfWeek = tournament['dayOfWeek'];
    final hour = tournament['hour'];
    final minute = tournament['minute'];

    var next = DateTime.utc(now.year, now.month, now.day, hour, minute).toLocal();
    while (next.weekday != dayOfWeek) {
      next = next.add(const Duration(days: 1));
    }
    if (!next.isAfter(now)) next = next.add(const Duration(days: 7));

    final diff = next.difference(now);
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;

    if (days > 0) return 'In ${days}d ${hours}h ${minutes}m';
    if (hours > 0) return 'In ${hours}h ${minutes}m';
    return 'In ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Map<String, dynamic>>(
        future: _data,
        builder: (context, snapshot) {
          final memberCount = snapshot.data?['memberCount'] ?? '...';
          final tournament = snapshot.data?['tournament'];
          final lastWinner = snapshot.data?['lastWinner'];
          final nextTournament = tournament != null ? _getNextTournament(tournament) : '...';
          final tournamentName = tournament?['name'] ?? 'Tournament';

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 200,
                floating: false,
                pinned: true,
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            backgroundColor: const Color(0xFF12121A),
                            title: Text(widget.user.nickname,
                                style: const TextStyle(color: Colors.white)),
                            content: Text('@${widget.user.username}',
                                style: const TextStyle(color: Colors.white54)),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: CircleAvatar(
                        radius: 18,
                        backgroundImage: widget.user.avatar != null
                            ? NetworkImage(widget.user.avatar!)
                            : null,
                        backgroundColor: const Color(0xFF6C63FF),
                        child: widget.user.avatar == null
                            ? Text(widget.user.username[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white))
                            : null,
                      ),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  title: const Text('Fusion Esports',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF0A0A0F)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Welcome message
                    Text(
                      'Welcome back, ${widget.user.nickname}!',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 15),
                    ),
                    const SizedBox(height: 16),
                    _InfoCard(
                      icon: Icons.people,
                      title: 'Discord Members',
                      value: memberCount.toString(),
                      color: const Color(0xFF6C63FF),
                    ),
                    const SizedBox(height: 12),
                    _InfoCard(
                      icon: Icons.emoji_events,
                      title: 'Next $tournamentName',
                      value: nextTournament,
                      color: const Color(0xFFFF6B6B),
                    ),
                    const SizedBox(height: 12),
                    if (lastWinner != null)
                      _InfoCard(
                        icon: Icons.military_tech,
                        title: 'Last Winner',
                        value: lastWinner['first'] ?? 'TBD',
                        color: const Color(0xFFFFD700),
                      ),
                    const SizedBox(height: 24),
                    const Text('Socials',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    if (snapshot.data != null)
                      ...List<Map<String, dynamic>>.from(snapshot.data!['socials'])
                          .map((social) => _SocialCard(social: social)),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white54, fontSize: 13)),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SocialCard extends StatelessWidget {
  final Map<String, dynamic> social;

  const _SocialCard({required this.social});

  IconData _getIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube': return Icons.play_circle_fill;
      case 'twitter': return Icons.alternate_email;
      case 'instagram': return Icons.camera_alt;
      case 'website': return Icons.language;
      default: return Icons.link;
    }
  }

  Color _getColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube': return const Color(0xFFFF0000);
      case 'twitter': return const Color(0xFF1DA1F2);
      case 'instagram': return const Color(0xFFE1306C);
      case 'website': return const Color(0xFF6C63FF);
      default: return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    final platform = social['platform'] ?? '';
    final color = _getColor(platform);
    final url = social['url'] ?? '';

    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF12121A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(_getIcon(platform), color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(social['name'] ?? '',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(social['desc'] ?? '',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
          ],
        ),
      ),
    );
  }
}

// ── SCHEDULE PAGE ──────────────────────────────────────────────────────────
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  late Future<Map<String, dynamic>> _data;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _data = fetchBinData();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _getCountdown(Map<String, dynamic> tournament) {
    final now = DateTime.now();
    final dayOfWeek = tournament['dayOfWeek'];
    final hour = tournament['hour'];
    final minute = tournament['minute'];

    var next = DateTime.utc(now.year, now.month, now.day, hour, minute).toLocal();
    while (next.weekday != dayOfWeek) {
      next = next.add(const Duration(days: 1));
    }
    if (!next.isAfter(now)) next = next.add(const Duration(days: 7));

    final diff = next.difference(now);
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;
    final seconds = diff.inSeconds % 60;

    if (days > 0) return '${days}d ${hours}h ${minutes}m ${seconds}s';
    if (hours > 0) return '${hours}h ${minutes}m ${seconds}s';
    return '${minutes}m ${seconds}s';
  }

  String _getWeekdayName(int day) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[day - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule'),
        backgroundColor: const Color(0xFF12121A),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _data,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final tournament = snapshot.data!['tournament'];
          final lastWinner = snapshot.data!['lastWinner'];
          final weekday = _getWeekdayName(tournament['dayOfWeek']);
          final hour = tournament['hour'];
          final minute = tournament['minute'].toString().padLeft(2, '0');
          final upcomingCount = tournament['upcomingCount'];
          final countdown = _getCountdown(tournament);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF3D35CC)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Text('Next Tournament',
                          style: TextStyle(color: Colors.white70, fontSize: 14)),
                      const SizedBox(height: 8),
                      Text(tournament['name'],
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Text(countdown,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2)),
                      const SizedBox(height: 8),
                      Text('Every $weekday at ${hour}:$minute UTC',
                          style: const TextStyle(color: Colors.white60, fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _ScheduleInfoRow(
                  icon: Icons.event,
                  label: 'Upcoming Tournaments',
                  value: upcomingCount.toString(),
                  color: const Color(0xFF6C63FF),
                ),
                const SizedBox(height: 12),
                _ScheduleInfoRow(
                  icon: Icons.repeat,
                  label: 'Frequency',
                  value: 'Weekly every $weekday',
                  color: const Color(0xFFFF6B6B),
                ),
                const SizedBox(height: 12),
                _ScheduleInfoRow(
                  icon: Icons.access_time,
                  label: 'Start Time',
                  value: '${hour}:$minute UTC (${hour + 1}:$minute CET)',
                  color: const Color(0xFF4CAF50),
                ),
                const SizedBox(height: 24),
                const Text('Last Tournament Results',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (lastWinner != null) ...[
                  _WinnerCard(
                    place: '🥇 1st',
                    name: lastWinner['first'] ?? 'TBD',
                    color: const Color(0xFFFFD700),
                  ),
                  const SizedBox(height: 8),
                  _WinnerCard(
                    place: '🥈 2nd',
                    name: lastWinner['second'] ?? 'TBD',
                    color: const Color(0xFFB0BEC5),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF12121A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(lastWinner['note'] ?? '',
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(lastWinner['date'] ?? '',
                            style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ScheduleInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _ScheduleInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _WinnerCard extends StatelessWidget {
  final String place;
  final String name;
  final Color color;

  const _WinnerCard({
    required this.place,
    required this.name,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Text(place,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(width: 12),
          Text(name,
              style: const TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
    );
  }
}

// ── STATS PAGE ─────────────────────────────────────────────────────────────
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Player Stats'),
        backgroundColor: const Color(0xFF12121A),
      ),
      body: const Center(
        child: Text('Stats coming soon',
            style: TextStyle(color: Colors.white54)),
      ),
    );
  }
}

// ── NEWS PAGE ──────────────────────────────────────────────────────────────
class NewsPage extends StatelessWidget {
  const NewsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('News'),
        backgroundColor: const Color(0xFF12121A),
      ),
      body: const Center(
        child: Text('News coming soon',
            style: TextStyle(color: Colors.white54)),
      ),
    );
  }
}