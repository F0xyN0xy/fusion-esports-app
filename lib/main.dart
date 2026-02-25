import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
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
        Uri.parse(
          'https://fusion-esports.netlify.app/api/discord_auth?code=$code',
        ),
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
              Text(
                'Logging you in...',
                style: TextStyle(color: Colors.white54),
              ),
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
class LoginPage extends StatefulWidget {
  final VoidCallback onLogin;

  const LoginPage({super.key, required this.onLogin});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _accepted = false;

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
                        color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
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
                // ToS acceptance
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: _accepted,
                      onChanged: (val) =>
                          setState(() => _accepted = val ?? false),
                      activeColor: const Color(0xFF6C63FF),
                      side: const BorderSide(color: Colors.white38),
                    ),
                    Expanded(
                      child: Wrap(
                        children: [
                          const Text(
                            'I agree to the ',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => launchUrl(
                              Uri.parse(
                                'https://fusion-esports.netlify.app/terms',
                              ),
                              mode: LaunchMode.externalApplication,
                            ),
                            child: const Text(
                              'Terms of Service',
                              style: TextStyle(
                                color: Color(0xFF6C63FF),
                                fontSize: 13,
                                decoration: TextDecoration.underline,
                                decorationColor: Color(0xFF6C63FF),
                              ),
                            ),
                          ),
                          const Text(
                            ' and ',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => launchUrl(
                              Uri.parse(
                                'https://fusion-esports.netlify.app/privacy',
                              ),
                              mode: LaunchMode.externalApplication,
                            ),
                            child: const Text(
                              'Privacy Policy',
                              style: TextStyle(
                                color: Color(0xFF6C63FF),
                                fontSize: 13,
                                decoration: TextDecoration.underline,
                                decorationColor: Color(0xFF6C63FF),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Login button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _accepted ? widget.onLogin : null,
                    icon: const Icon(Icons.discord, size: 24),
                    label: const Text(
                      'Login with Discord',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5865F2),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(
                        0xFF5865F2,
                      ).withValues(alpha: 0.3),
                      disabledForegroundColor: Colors.white38,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Join Discord button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse('https://discord.gg/Nsng7acTP7'),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(
                      Icons.group_add,
                      size: 20,
                      color: Colors.white54,
                    ),
                    label: const Text(
                      'Join our Discord first',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
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
      StatsPage(user: widget.user),
      const NewsPage(),
      SettingsPage(user: widget.user, onLogout: widget.onLogout),
    ];

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF12121A),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.calendar_month),
            label: 'Schedule',
          ),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Stats'),
          NavigationDestination(icon: Icon(Icons.newspaper), label: 'News'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
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

    var next = DateTime.utc(
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    ).toLocal();
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
          final nextTournament = tournament != null
              ? _getNextTournament(tournament)
              : '...';
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
                            title: Text(
                              widget.user.nickname,
                              style: const TextStyle(color: Colors.white),
                            ),
                            content: Text(
                              '@${widget.user.username}',
                              style: const TextStyle(color: Colors.white54),
                            ),
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
                            ? Text(
                                widget.user.username[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  title: const Text(
                    'Fusion Esports',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
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
                        color: Colors.white70,
                        fontSize: 15,
                      ),
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
                    const Text(
                      'Socials',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (snapshot.data != null)
                      ...List<Map<String, dynamic>>.from(
                        snapshot.data!['socials'],
                      ).map((social) => _SocialCard(social: social)),
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
              Text(
                title,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
      case 'youtube':
        return Icons.play_circle_fill;
      case 'twitter':
        return Icons.alternate_email;
      case 'instagram':
        return Icons.camera_alt;
      case 'website':
        return Icons.language;
      default:
        return Icons.link;
    }
  }

  Color _getColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return const Color(0xFFFF0000);
      case 'twitter':
        return const Color(0xFF1DA1F2);
      case 'instagram':
        return const Color(0xFFE1306C);
      case 'website':
        return const Color(0xFF6C63FF);
      default:
        return Colors.white54;
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
                  Text(
                    social['name'] ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    social['desc'] ?? '',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: Colors.white24,
              size: 14,
            ),
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

    var next = DateTime.utc(
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    ).toLocal();
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
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
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
                      const Text(
                        'Next Tournament',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tournament['name'],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        countdown,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Every $weekday at $hour:$minute UTC',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                        ),
                      ),
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
                  value: '$hour:$minute UTC (${hour + 1}:$minute CET)',
                  color: const Color(0xFF4CAF50),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Last Tournament Results',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                        Text(
                          lastWinner['note'] ?? '',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lastWinner['date'] ?? '',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
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
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
          Text(
            place,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 12),
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
    );
  }
}

// ── STATS PAGE ─────────────────────────────────────────────────────────────
class StatsPage extends StatefulWidget {
  final DiscordUser user;

  const StatsPage({super.key, required this.user});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late Future<Map<String, dynamic>> _xpData;
  bool _showLeaderboard = false;

  @override
  void initState() {
    super.initState();
    _xpData = _fetchXPData();
  }

  Future<Map<String, dynamic>> _fetchXPData() async {
    final response = await http.get(
      Uri.parse('https://api.jsonbin.io/v3/b/${Config.xpBinId}/latest'),
      headers: {'X-Master-Key': Config.jsonBinApiKey},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['record'];
    }
    throw Exception('Failed to load XP data');
  }

  int _getLevel(int xp) => (0.1 * sqrt(xp.toDouble())).floor();
  int _xpForLevel(int level) => pow(level / 0.1, 2).toInt();
  int _xpForNextLevel(int level) => pow((level + 1) / 0.1, 2).toInt();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stats'),
        backgroundColor: const Color(0xFF12121A),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _xpData = _fetchXPData()),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _xpData,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'Failed to load stats',
                    style: TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => setState(() => _xpData = _fetchXPData()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final data = snapshot.data!;
          final myStats = data[widget.user.id];

          // Sort leaderboard
          final sorted = data.entries.toList()
            ..sort(
              (a, b) => (b.value['xp'] as int).compareTo(a.value['xp'] as int),
            );

          final myRank = sorted.indexWhere((e) => e.key == widget.user.id) + 1;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // My stats card
                if (myStats != null) ...[
                  _buildMyStatsCard(myStats, myRank),
                  const SizedBox(height: 24),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF12121A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Text(
                      'No stats yet — start chatting in the server to earn XP!',
                      style: TextStyle(color: Colors.white54),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Leaderboard toggle
                GestureDetector(
                  onTap: () =>
                      setState(() => _showLeaderboard = !_showLeaderboard),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF12121A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.leaderboard,
                          color: Color(0xFF6C63FF),
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Leaderboard',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          _showLeaderboard
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: Colors.white54,
                        ),
                      ],
                    ),
                  ),
                ),

                if (_showLeaderboard) ...[
                  const SizedBox(height: 8),
                  ...sorted.take(10).toList().asMap().entries.map((entry) {
                    final rank = entry.key + 1;
                    final userId = entry.value.key;
                    final stats = entry.value.value;
                    final xp = stats['xp'] as int;
                    final level = _getLevel(xp);
                    final isMe = userId == widget.user.id;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isMe
                            ? const Color(0xFF6C63FF).withValues(alpha: 0.15)
                            : const Color(0xFF12121A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isMe
                              ? const Color(0xFF6C63FF).withValues(alpha: 0.5)
                              : Colors.white12,
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text(
                              rank == 1
                                  ? '🥇'
                                  : rank == 2
                                  ? '🥈'
                                  : rank == 3
                                  ? '🥉'
                                  : '#$rank',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isMe
                                      ? widget.user.nickname
                                      : 'User #${userId.substring(userId.length - 4)}',
                                  style: TextStyle(
                                    color: isMe
                                        ? const Color(0xFF6C63FF)
                                        : Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Level $level • $xp XP',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMyStatsCard(Map<String, dynamic> stats, int rank) {
    final xp = stats['xp'] as int;
    final messages = stats['messages'] as int? ?? 0;
    final vcMinutes = stats['vcMinutes'] as int? ?? 0;
    final level = _getLevel(xp);
    final currentLevelXp = _xpForLevel(level);
    final nextLevelXp = _xpForNextLevel(level);
    final progress = (xp - currentLevelXp) / (nextLevelXp - currentLevelXp);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFF3D35CC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundImage: widget.user.avatar != null
                    ? NetworkImage(widget.user.avatar!)
                    : null,
                backgroundColor: Colors.white24,
                child: widget.user.avatar == null
                    ? Text(
                        widget.user.username[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.user.nickname,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Rank #$rank on the server',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Level $level',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // XP Progress bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$xp XP',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                '$nextLevelXp XP for Level ${level + 1}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),
          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem('Messages', messages.toString(), Icons.chat_bubble),
              _statItem('VC Time', '${vcMinutes}m', Icons.headset),
              _statItem('Total XP', xp.toString(), Icons.star),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

// ── NEWS PAGE ──────────────────────────────────────────────────────────────
class NewsPage extends StatefulWidget {
  const NewsPage({super.key});

  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  late Future<List<dynamic>> _announcements;

  @override
  void initState() {
    super.initState();
    _announcements = _fetchAnnouncements();
  }

  Future<List<dynamic>> _fetchAnnouncements() async {
    final response = await http.get(
      Uri.parse('https://fusion-esports.netlify.app/api/announcements'),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load announcements');
  }

  String _formatTime(String timestamp) {
    final date = DateTime.parse(timestamp).toLocal();
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays > 7) return '${date.day}/${date.month}/${date.year}';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Announcements'),
        backgroundColor: const Color(0xFF12121A),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                setState(() => _announcements = _fetchAnnouncements()),
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _announcements,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'Failed to load announcements',
                    style: TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () =>
                        setState(() => _announcements = _fetchAnnouncements()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final announcements = snapshot.data!;

          if (announcements.isEmpty) {
            return const Center(
              child: Text(
                'No announcements yet',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: announcements.length,
            itemBuilder: (context, index) {
              final a = announcements[index];
              final hasAttachments = (a['attachments'] as List).isNotEmpty;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF12121A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundImage: a['authorAvatar'] != null
                                ? NetworkImage(a['authorAvatar'])
                                : null,
                            backgroundColor: const Color(0xFF6C63FF),
                            child: a['authorAvatar'] == null
                                ? Text(
                                    (a['author'] as String)[0].toUpperCase(),
                                    style: const TextStyle(color: Colors.white),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a['author'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _formatTime(a['timestamp']),
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Content
                    if (a['content'] != null && a['content'].isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          a['content'],
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.5,
                          ),
                        ),
                      ),

                    // Attachments
                    if (hasAttachments)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            a['attachments'][0],
                            fit: BoxFit.cover,
                            width: double.infinity,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 12),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ── SETTINGS PAGE ──────────────────────────────────────────────────────────
class SettingsPage extends StatefulWidget {
  final DiscordUser user;
  final VoidCallback onLogout;

  const SettingsPage({super.key, required this.user, required this.onLogout});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;
  bool _isDarkMode = true;
  Set<String> _userRoles = {};
  bool _rolesLoading = false;

  static const Map<String, Map<String, dynamic>> _availableRoles = {
    // Ranks
    '1472256135498174484': {
      'name': 'SSL',
      'category': 'Rank',
      'color': Color(0xFFFF6B6B),
    },
    '1472256020033175733': {
      'name': 'GC',
      'category': 'Rank',
      'color': Color(0xFFFF6B6B),
    },
    '1472255906895888536': {
      'name': 'Champion',
      'category': 'Rank',
      'color': Color(0xFF9B59B6),
    },
    '1472255796149751895': {
      'name': 'Diamond',
      'category': 'Rank',
      'color': Color(0xFF5DADE2),
    },
    '1472255689496727624': {
      'name': 'Platinum',
      'category': 'Rank',
      'color': Color(0xFF48C9B0),
    },
    '1472255533095321680': {
      'name': 'Gold',
      'category': 'Rank',
      'color': Color(0xFFFFD700),
    },
    '1472255376446460097': {
      'name': 'Silver',
      'category': 'Rank',
      'color': Color(0xFFBDC3C7),
    },
    '1472255257550786610': {
      'name': 'Bronze',
      'category': 'Rank',
      'color': Color(0xFFCD7F32),
    },
    // Regions
    '1472258075699450009': {
      'name': 'EU',
      'category': 'Region',
      'color': Color(0xFF3498DB),
    },
    '1472258189054447707': {
      'name': 'NA',
      'category': 'Region',
      'color': Color(0xFFE74C3C),
    },
    '1472258244725444711': {
      'name': 'MENA',
      'category': 'Region',
      'color': Color(0xFF2ECC71),
    },
    '1472258344659193927': {
      'name': 'Other',
      'category': 'Region',
      'color': Color(0xFF95A5A6),
    },
    // Platforms
    '1472258403094106132': {
      'name': 'PC',
      'category': 'Platform',
      'color': Color(0xFF6C63FF),
    },
    '1472258460484898978': {
      'name': 'PlayStation',
      'category': 'Platform',
      'color': Color(0xFF003087),
    },
    '1472258609797922917': {
      'name': 'Xbox',
      'category': 'Platform',
      'color': Color(0xFF107C10),
    },
    '1472258550255325367': {
      'name': 'Switch',
      'category': 'Platform',
      'color': Color(0xFFE4000F),
    },
    // Notifications
    '1474677783572516984': {
      'name': 'Tournaments',
      'category': 'Notifications',
      'color': Color(0xFFFF6B6B),
    },
    '1474678114033340559': {
      'name': 'Scrims',
      'category': 'Notifications',
      'color': Color(0xFF6C63FF),
    },
    '1474678614367932426': {
      'name': 'YouTube',
      'category': 'Notifications',
      'color': Color(0xFFFF0000),
    },
  };

  @override
  void initState() {
    super.initState();
    _userRoles = Set<String>.from(widget.user.roles);
  }

  Future<void> _toggleRole(String roleId, bool add) async {
    setState(() => _rolesLoading = true);
    try {
      final response = await http.post(
        Uri.parse('https://fusion-esports.netlify.app/api/manage_roles'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': widget.user.id,
          'roleId': roleId,
          'action': add ? 'add' : 'remove',
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          if (add) {
            _userRoles.add(roleId);
          } else {
            _userRoles.remove(roleId);
          }
        });
      } else {
        _showError('Failed to update role. Please try again.');
      }
    } catch (e) {
      _showError('Something went wrong.');
    } finally {
      setState(() => _rolesLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Widget _buildRoleCategory(
    String category,
    List<MapEntry<String, Map<String, dynamic>>> roles,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            category,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF12121A),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: roles.map((entry) {
              final roleId = entry.key;
              final role = entry.value;
              final isSelected = _userRoles.contains(roleId);
              final color = role['color'] as Color;

              return GestureDetector(
                onTap: _rolesLoading
                    ? null
                    : () => _toggleRole(roleId, !isSelected),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.2)
                        : const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? color : Colors.white12,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    role['name'] as String,
                    style: TextStyle(
                      color: isSelected ? color : Colors.white54,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Group roles by category
    final categories = <String, List<MapEntry<String, Map<String, dynamic>>>>{};
    for (final entry in _availableRoles.entries) {
      final category = entry.value['category'] as String;
      categories.putIfAbsent(category, () => []).add(entry);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF12121A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF12121A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF6C63FF).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundImage: widget.user.avatar != null
                        ? NetworkImage(widget.user.avatar!)
                        : null,
                    backgroundColor: const Color(0xFF6C63FF),
                    child: widget.user.avatar == null
                        ? Text(
                            widget.user.username[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.user.nickname,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '@${widget.user.username}',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // App settings
            const Text(
              'APP',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF12121A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text(
                      'Push Notifications',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Receive app notifications',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: _notificationsEnabled,
                    activeThumbColor: const Color(0xFF6C63FF),
                    onChanged: (val) =>
                        setState(() => _notificationsEnabled = val),
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  SwitchListTile(
                    title: const Text(
                      'Dark Mode',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Toggle dark/light theme',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: _isDarkMode,
                    activeThumbColor: const Color(0xFF6C63FF),
                    onChanged: (val) => setState(() => _isDarkMode = val),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Roles section
            Row(
              children: [
                const Text(
                  'YOUR ROLES',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                if (_rolesLoading) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF6C63FF),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            ...categories.entries.map(
              (e) => _buildRoleCategory(e.key, e.value),
            ),

            const SizedBox(height: 8),

            // About section
            const Text(
              'ABOUT',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF12121A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    title: const Text(
                      'Version',
                      style: TextStyle(color: Colors.white),
                    ),
                    trailing: const Text(
                      '2.3.2',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  ListTile(
                    title: const Text(
                      'Fusion Esports',
                      style: TextStyle(color: Colors.white),
                    ),
                    trailing: const Text(
                      '© 2026',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Logout button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: const Color(0xFF12121A),
                      title: const Text(
                        'Logout',
                        style: TextStyle(color: Colors.white),
                      ),
                      content: const Text(
                        'Are you sure you want to logout?',
                        style: TextStyle(color: Colors.white54),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onLogout();
                          },
                          child: const Text(
                            'Logout',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.logout, color: Colors.white),
                label: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.red.withOpacity(0.5)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
