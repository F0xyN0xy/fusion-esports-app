import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
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
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const HomePage(),
    const SchedulePage(),
    const StatsPage(),
    const NewsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
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
const String _binId = Config.jsonBinId;
const String _apiKey = Config.jsonBinApiKey;

Future<Map<String, dynamic>> fetchBinData() async {
  final response = await http.get(
    Uri.parse('https://api.jsonbin.io/v3/b/$_binId/latest'),
    headers: {'X-Master-Key': _apiKey},
  );
  if (response.statusCode == 200) {
    return jsonDecode(response.body)['record'];
  }
  throw Exception('Failed to load data');
}

// ── HOME PAGE ──────────────────────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});

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

  // Tournament time is UK time (UTC), convert to local time
  var next = DateTime.utc(now.year, now.month, now.day, hour, minute).toLocal();

  // Find the next correct weekday
  while (next.weekday != dayOfWeek) {
    next = next.add(const Duration(days: 1));
  }

  // If that time has already passed, add 7 days
  if (!next.isAfter(now)) {
    next = next.add(const Duration(days: 7));
  }

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
                        title: 'Last Tournament Winner',
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
  String _countdown = '';

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
                // Countdown card
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

                // Upcoming count
                _ScheduleInfoRow(
                  icon: Icons.event,
                  label: 'Upcoming Tournaments',
                  value: upcomingCount.toString(),
                  color: const Color(0xFF6C63FF),
                ),
                const SizedBox(height: 12),

                // Schedule info
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

                // Last winner section
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
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(lastWinner['date'] ?? '',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
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