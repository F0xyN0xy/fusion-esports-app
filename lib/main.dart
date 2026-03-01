import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'firebase_options.dart';
import 'config.dart';
import 'feedback_system.dart';
import 'discord_chat.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const FusionApp());
}

// ── USER MODEL ──────────────────────────────────────────────���──────────────
class DiscordUser {
  final String id;
  final String username;
  final String? avatar;
  final String nickname;
  final List<String> roles;
  final String accessToken;

  const DiscordUser({
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
class FusionApp extends StatefulWidget {
  const FusionApp({super.key});

  static _FusionAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_FusionAppState>();

  @override
  State<FusionApp> createState() => _FusionAppState();
}

class _FusionAppState extends State<FusionApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fusion Esports',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF12121A),
        ),
      ),
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
        ),
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
  bool _isLoading = true;
  late AppLinks _appLinks;
  StreamSubscription? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _loadSavedUser();
    _initDeepLinks();
    _setupNotifications(); // add this
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('saved_user');
    if (userJson != null) {
      try {
        final savedUser = DiscordUser.fromJson(jsonDecode(userJson));
        setState(() {
          _user = savedUser;
          _isLoading = false;
        });
        // Refresh profile in background
        _refreshUserProfile(savedUser.accessToken);
      } catch (_) {
        setState(() => _isLoading = false);
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshUserProfile(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse(
            '${Config.discordAuthEndpoint}?refresh=true&token=$accessToken'),
      );
      if (response.statusCode == 200) {
        final updatedUser = DiscordUser.fromJson(jsonDecode(response.body));
        await _saveUser(updatedUser);
        setState(() => _user = updatedUser);
      }
    } catch (_) {
      // Silently fail — user stays logged in with cached data
    }
  }

  Future<void> _saveUser(DiscordUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'saved_user',
        jsonEncode({
          'id': user.id,
          'username': user.username,
          'avatar': user.avatar,
          'nickname': user.nickname,
          'roles': user.roles,
          'accessToken': user.accessToken,
        }));
  }

  Future<void> _clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_user');
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
        Uri.parse('${Config.discordAuthEndpoint}?code=$code'),
      );

      if (response.statusCode == 200) {
        final user = DiscordUser.fromJson(jsonDecode(response.body));
        await _saveUser(user);
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
  Future<void> _setupNotifications() async {
  final messaging = FirebaseMessaging.instance;

  await messaging.requestPermission();

  await messaging.subscribeToTopic('all');
  await messaging.subscribeToTopic('tournaments');
  await messaging.subscribeToTopic('scrims');
  await messaging.subscribeToTopic('coaching');

  FirebaseMessaging.onMessage.listen((message) {
    if (message.notification != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.notifications, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.notification!.title ?? '',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      message.notification!.body ?? '',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF6C63FF),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _loginWithDiscord() async {
    await launchUrl(
      Uri.parse(Config.discordAuthUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  void _logout() async {
    await _clearUser();
    setState(() => _user = null);
  }

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
              Text('Loading...', style: TextStyle(color: Colors.white54)),
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

// ── LOGIN PAGE ───────────��─────────────────────────────────────────────────
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
                    icon: const Icon(Icons.login, size: 24),
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
                      ).withOpacity(0.3),
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
    final isBetaTester = DiscordChatSystem.isAuthorizedBetaTester(widget.user);

    final pages = [
      HomePage(user: widget.user),
      const SchedulePage(),
      StatsPage(user: widget.user),
      const NewsPage(),
      // Chat page - locked or unlocked
      isBetaTester
          ? DiscordChatPage(user: widget.user)
          : const LockedChatPage(),
      SettingsPage(user: widget.user, onLogout: widget.onLogout),
    ];

    final destinations = [
      const NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
      const NavigationDestination(
          icon: Icon(Icons.calendar_month), label: 'Schedule'),
      const NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Stats'),
      const NavigationDestination(icon: Icon(Icons.newspaper), label: 'News'),
      // Chat with lock indicator
      NavigationDestination(
        icon: Icon(
          isBetaTester ? Icons.chat_bubble : Icons.lock_outline,
          color: isBetaTester ? null : Colors.orange,
        ),
        label: isBetaTester ? 'Chat' : 'Locked',
      ),
      const NavigationDestination(
          icon: Icon(Icons.settings), label: 'Settings'),
    ];

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          // Prevent accessing locked chat
          if (index == 4 && !isBetaTester) {
            _showLockedMessage();
            return;
          }
          setState(() => _currentIndex = index);
        },
        backgroundColor: const Color(0xFF12121A),
        destinations: destinations,
      ),
    );
  }

  void _showLockedMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🔒 Beta chat is locked. Full release coming soon.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
  }
}

// ── DATA FETCHING ──────────────────────────────────────────────────────────
Future<Map<String, dynamic>> fetchBinData() async {
  final response = await http.get(
    Uri.parse(Config.jsonBinUrl),
    headers: {'X-Master-Key': Config.jsonBinApiKey},
  );
  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);
    final raw = (decoded is Map && decoded.containsKey('record'))
        ? decoded['record']
        : decoded;
    if (raw is Map<String, dynamic>) {
      return _normalizeBinData(raw);
    }
    // If unexpected shape, still try to wrap into defaults
    return _normalizeBinData({});
  }
  throw Exception('Failed to load data');
}

Map<String, dynamic> _normalizeBinData(Map<String, dynamic> raw) {
  // Helper getters
  int toInt(dynamic v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is double) return v.floor();
    if (v is String) {
      final p = int.tryParse(v.trim());
      if (p != null) return p;
    }
    return fallback;
  }

  String toStr(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    return v.toString();
  }

  List<Map<String, dynamic>> toListOfMap(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e is Map<String, dynamic>
              ? e
              : e is Map
                  ? Map<String, dynamic>.from(e)
                  : <String, dynamic>{})
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  Map<String, dynamic> getMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  // memberCount
  final stats = getMap(raw['stats']);
  final memberCount = toInt(
    raw['memberCount'] ?? raw['membersCount'] ?? raw['guildMembers'] ?? stats['members'] ?? 0,
  );

  // socials
  final socialsSrc = raw['socials'] ?? raw['links'] ?? raw['social'] ?? [];
  final socials = toListOfMap(socialsSrc).map((s) {
    final platform = toStr(s['platform'] ?? s['service'] ?? s['type'] ?? 'website');
    final url = toStr(s['url'] ?? s['link'] ?? s['href'] ?? '');
    final name = toStr(s['name'] ?? s['title'] ?? s['label'] ?? platform);
    final desc = toStr(s['desc'] ?? s['description'] ?? '');
    return {
      'platform': platform,
      'url': url,
      'name': name,
      'desc': desc,
    };
  }).toList();

  // tournament
  Map<String, dynamic> tournamentSrc = getMap(
    raw['tournament'] ?? getMap(raw['events'])['tournament'] ?? raw['nextTournament'],
  );
  String tName = toStr(tournamentSrc['name'] ?? tournamentSrc['title'] ?? 'Tournament');
  dynamic dayAny = tournamentSrc['dayOfWeek'] ?? tournamentSrc['weekday'] ?? tournamentSrc['day'];
  int dayOfWeek;
  if (dayAny is String) {
    const days = {
      'monday': 1,
      'tuesday': 2,
      'wednesday': 3,
      'thursday': 4,
      'friday': 5,
      'saturday': 6,
      'sunday': 7,
    };
    dayOfWeek = days[dayAny.toLowerCase()] ?? 1;
  } else {
    dayOfWeek = toInt(dayAny, 1);
  }
  int hour = toInt(tournamentSrc['hour'] ?? tournamentSrc['startHour'], 18);
  int minute = toInt(tournamentSrc['minute'] ?? tournamentSrc['startMinute'], 0);
  final startStr = toStr(tournamentSrc['start']);
  if (startStr.contains(':')) {
    final parts = startStr.split(':');
    if (parts.isNotEmpty) hour = int.tryParse(parts[0]) ?? hour;
    if (parts.length > 1) minute = int.tryParse(parts[1]) ?? minute;
  }
  final upcomingCount = toInt(
    tournamentSrc['upcomingCount'] ?? tournamentSrc['occurrences'] ?? tournamentSrc['upcoming'] ?? 0,
  );
  final tournament = {
    'name': tName,
    'dayOfWeek': dayOfWeek.clamp(1, 7),
    'hour': hour.clamp(0, 23),
    'minute': minute.clamp(0, 59),
    'upcomingCount': upcomingCount < 0 ? 0 : upcomingCount,
  };

  // lastWinner
  final winnersRaw = raw['lastWinner'] ?? raw['winners'] ?? raw['lastWinners'];
  Map<String, dynamic> lastWinner = {};
  if (winnersRaw is Map) {
    final w = getMap(winnersRaw);
    lastWinner = {
      'first': toStr(w['first'] ?? w['1st'] ?? w['gold'] ?? ''),
      'second': toStr(w['second'] ?? w['2nd'] ?? w['silver'] ?? ''),
      'date': toStr(w['date'] ?? w['timestamp'] ?? ''),
      'note': toStr(w['note'] ?? w['details'] ?? ''),
    };
  } else if (winnersRaw is List) {
    final list = winnersRaw.cast<dynamic>();
    String first = list.isNotEmpty ? toStr(getMap(list[0])['name'] ?? list[0]) : '';
    String second = list.length > 1 ? toStr(getMap(list[1])['name'] ?? list[1]) : '';
    lastWinner = {
      'first': first,
      'second': second,
      'date': '',
      'note': '',
    };
  } else {
    lastWinner = {'first': '', 'second': '', 'date': '', 'note': ''};
  }

  // scrims
  final scrimsSrc = raw['scrims'] ?? getMap(raw['events'])['scrims'] ?? [];
  final scrims = toListOfMap(scrimsSrc).map((s) {
    final date = toStr(s['date'] ?? s['day'] ?? '');
    final time = toStr(s['time'] ?? s['start'] ?? '');
    final status = toStr(s['status'] ?? s['state'] ?? 'open');
    final rank = toStr(s['rank'] ?? s['mmr'] ?? 'All ranks');
    final format = toStr(s['format'] ?? s['mode'] ?? 'Scrim');
    final spots = toInt(s['spots'] ?? s['available'] ?? s['capacity'], 0);
    return {
      'date': date,
      'time': time,
      'status': status.isEmpty ? 'open' : status,
      'rank': rank.isEmpty ? 'All ranks' : rank,
      'format': format.isEmpty ? 'Scrim' : format,
      'spots': spots > 0 ? spots : null,
    };
  }).toList();

  // coaching
  final coachingSrc = raw['coaching'] ?? getMap(raw['events'])['coaching'] ?? [];
  final coaching = toListOfMap(coachingSrc).map((c) {
    final date = toStr(c['date'] ?? c['day'] ?? '');
    final time = toStr(c['time'] ?? c['start'] ?? '');
    final coach = toStr(c['coach'] ?? c['host'] ?? '');
    final topic = toStr(c['topic'] ?? c['subject'] ?? 'Coaching Session');
    final rank = toStr(c['rank'] ?? 'All ranks');
    final spots = toInt(c['spots'] ?? c['available'] ?? c['capacity'], 0);
    return {
      'date': date,
      'time': time,
      'coach': coach,
      'topic': topic,
      'rank': rank.isEmpty ? 'All ranks' : rank,
      'spots': spots > 0 ? spots : null,
    };
  }).toList();

  return {
    'memberCount': memberCount,
    'socials': socials,
    'tournament': tournament,
    'lastWinner': lastWinner,
    'scrims': scrims,
    'coaching': coaching,
  };
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
  Timer? _timer;
  Duration _timeUntilTournament = Duration.zero;
  Map<String, dynamic>? _tournament;

  @override
  void initState() {
    super.initState();
    _data = fetchBinData();
    _data.then((data) {
      _tournament = data['tournament'];
      _updateCountdown();
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _updateCountdown(),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateCountdown() {
    if (_tournament == null) return;
    final now = DateTime.now();
    var next = DateTime.utc(
      now.year,
      now.month,
      now.day,
      _tournament!['hour'],
      _tournament!['minute'],
    ).toLocal();
    while (next.weekday != _tournament!['dayOfWeek']) {
      next = next.add(const Duration(days: 1));
    }
    if (!next.isAfter(now)) next = next.add(const Duration(days: 7));
    setState(() => _timeUntilTournament = next.difference(now));
  }

  String get _countdownText {
    final d = _timeUntilTournament;
    if (d.inDays > 0) {
      return '${d.inDays}d ${d.inHours % 24}h ${d.inMinutes % 60}m';
    }
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes % 60}m ${d.inSeconds % 60}s';
    }
    return '${d.inMinutes}m ${d.inSeconds % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _data,
        builder: (context, snapshot) {
          final memberCount = snapshot.data?['memberCount'] ?? '...';
          final lastWinner = snapshot.data?['lastWinner'];
          final tournamentName =
              snapshot.data?['tournament']?['name'] ?? 'Tournament';
          final socials = snapshot.data != null
              ? List<Map<String, dynamic>>.from(snapshot.data!['socials'])
              : <Map<String, dynamic>>[];

          return CustomScrollView(
            slivers: [
              // ── HEADER ──
              SliverAppBar(
                expandedHeight: 220,
                floating: false,
                pinned: true,
                backgroundColor: const Color(0xFF0A0A0F),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: () => showDialog(
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
                      ),
                      child: CircleAvatar(
                        radius: 20,
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
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF3D35CC),
                          Color(0xFF6C63FF),
                          Color(0xFF0A0A0F),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 0.4, 1.0],
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.asset(
                                    'assets/icon.png',
                                    width: 48,
                                    height: 48,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Fusion Esports',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Welcome back, ${widget.user.nickname}! 👋',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // ── STATS GRID ──
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            icon: Icons.people_alt_rounded,
                            label: 'Members',
                            value: memberCount.toString(),
                            color: const Color(0xFF6C63FF),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.emoji_events_rounded,
                            label: 'Next $tournamentName',
                            value:
                                snapshot.data != null ? _countdownText : '...',
                            color: const Color(0xFFFF6B6B),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // ── LAST WINNER ──
                    if (lastWinner != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFFFD700).withOpacity(0.15),
                              const Color(0xFF12121A),
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(
                              0xFFFFD700,
                            ).withOpacity(0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFFD700,
                                ).withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.military_tech_rounded,
                                color: Color(0xFFFFD700),
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Last Tournament Winner',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    lastWinner['first'] ?? 'TBD',
                                    style: const TextStyle(
                                      color: Color(0xFFFFD700),
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (lastWinner['date'] != null)
                                    Text(
                                      lastWinner['date'],
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.workspace_premium_rounded,
                              color: Color(0xFFFFD700),
                              size: 32,
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 24),

                    // ── SOCIALS ──
                    const Text(
                      'Socials',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...socials.map((social) => _SocialCard(social: social)),
                    const SizedBox(height: 16),
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

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
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

    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(social['url'] ?? '');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF12121A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_getIcon(platform), color: color, size: 22),
            ),
            const SizedBox(width: 14),
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
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: color.withOpacity(0.5),
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
  String _selectedTab = 'tournament';

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
    var next = DateTime.utc(
      now.year,
      now.month,
      now.day,
      tournament['hour'],
      tournament['minute'],
    ).toLocal();
    while (next.weekday != tournament['dayOfWeek']) {
      next = next.add(const Duration(days: 1));
    }
    if (!next.isAfter(now)) next = next.add(const Duration(days: 7));
    final diff = next.difference(now);
    if (diff.inDays > 0) {
      return '${diff.inDays}d ${diff.inHours % 24}h ${diff.inMinutes % 60}m ${diff.inSeconds % 60}s';
    }
    if (diff.inHours > 0) {
      return '${diff.inHours}h ${diff.inMinutes % 60}m ${diff.inSeconds % 60}s';
    }
    return '${diff.inMinutes}m ${diff.inSeconds % 60}s';
  }

  String _getWeekdayName(int day) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    return days[day - 1];
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return const Color(0xFF4CAF50);
      case 'full':
        return const Color(0xFFFF6B6B);
      case 'cancelled':
        return Colors.white38;
      default:
        return const Color(0xFF6C63FF);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule'),
        backgroundColor: const Color(0xFF12121A),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _data = fetchBinData()),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _data,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFF6C63FF)));
          }

          final tournament = snapshot.data!['tournament'];
          final lastWinner = snapshot.data!['lastWinner'];
          final scrims =
              List<Map<String, dynamic>>.from(snapshot.data!['scrims'] ?? []);
          final coaching =
              List<Map<String, dynamic>>.from(snapshot.data!['coaching'] ?? []);
          final weekday = _getWeekdayName(tournament['dayOfWeek']);
          final hour = tournament['hour'];
          final minute = tournament['minute'].toString().padLeft(2, '0');

          // Filter upcoming scrims
          final now = DateTime.now();
          final upcomingScrims = scrims.where((s) {
            try {
              final dateStr = '${s['date']} ${s['time']}';
              final parsed = DateTime.tryParse(dateStr.replaceAll('/', '-'));
              return parsed != null &&
                  parsed.isAfter(now) &&
                  s['status'] != 'cancelled';
            } catch (_) {
              return true;
            }
          }).toList();

          return Column(
            children: [
              // ── TAB BAR ──
              Container(
                color: const Color(0xFF12121A),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    _TabButton(
                        label: 'Tournament',
                        icon: Icons.emoji_events,
                        selected: _selectedTab == 'tournament',
                        onTap: () =>
                            setState(() => _selectedTab = 'tournament')),
                    const SizedBox(width: 8),
                    _TabButton(
                        label: 'Scrims',
                        icon: Icons.sports_esports,
                        selected: _selectedTab == 'scrims',
                        onTap: () => setState(() => _selectedTab = 'scrims'),
                        badge: upcomingScrims.length),
                    const SizedBox(width: 8),
                    _TabButton(
                        label: 'Coaching',
                        icon: Icons.school,
                        selected: _selectedTab == 'coaching',
                        onTap: () => setState(() => _selectedTab = 'coaching')),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _selectedTab == 'tournament'
                      ? _buildTournamentTab(
                          tournament, lastWinner, weekday, hour, minute)
                      : _selectedTab == 'scrims'
                          ? _buildScrimsTab(upcomingScrims, scrims)
                          : _buildCoachingTab(coaching),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTournamentTab(dynamic tournament, dynamic lastWinner,
      String weekday, int hour, String minute) {
    return Column(
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
              Text(_getCountdown(tournament),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Text('Every $weekday at $hour:$minute UTC',
                  style: const TextStyle(color: Colors.white60, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _ScheduleInfoRow(
            icon: Icons.event,
            label: 'Upcoming Tournaments',
            value: tournament['upcomingCount'].toString(),
            color: const Color(0xFF6C63FF)),
        const SizedBox(height: 12),
        _ScheduleInfoRow(
            icon: Icons.repeat,
            label: 'Frequency',
            value: 'Weekly every $weekday',
            color: const Color(0xFFFF6B6B)),
        const SizedBox(height: 12),
        _ScheduleInfoRow(
            icon: Icons.access_time,
            label: 'Start Time',
            value: '$hour:$minute UTC (${hour + 1}:$minute CET)',
            color: const Color(0xFF4CAF50)),
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
              color: const Color(0xFFFFD700)),
          const SizedBox(height: 8),
          _WinnerCard(
              place: '🥈 2nd',
              name: lastWinner['second'] ?? 'TBD',
              color: const Color(0xFFB0BEC5)),
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
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text(lastWinner['date'] ?? '',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildScrimsTab(
      List<Map<String, dynamic>> upcoming, List<Map<String, dynamic>> all) {
    if (all.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(height: 60),
            Icon(Icons.sports_esports, color: Colors.white24, size: 64),
            SizedBox(height: 16),
            Text('No scrims scheduled',
                style: TextStyle(color: Colors.white54, fontSize: 16)),
            SizedBox(height: 8),
            Text('Check back later or ask a mod to add one!',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (upcoming.isNotEmpty) ...[
          const Text('Upcoming Scrims',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...upcoming.map((s) => _ScrimCard(
              scrim: s, statusColor: _getStatusColor(s['status'] ?? 'open'))),
        ],
        if (upcoming.length < all.length) ...[
          const SizedBox(height: 24),
          const Text('Past Scrims',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...all.where((s) => !upcoming.contains(s)).take(5).map((s) =>
              _ScrimCard(scrim: s, statusColor: Colors.white24, isPast: true)),
        ],
      ],
    );
  }

  Widget _buildCoachingTab(List<Map<String, dynamic>> coaching) {
    if (coaching.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(height: 60),
            Icon(Icons.school, color: Colors.white24, size: 64),
            SizedBox(height: 16),
            Text('No coaching sessions scheduled',
                style: TextStyle(color: Colors.white54, fontSize: 16)),
            SizedBox(height: 8),
            Text('Check back later!',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final upcoming = coaching.where((c) {
      try {
        final parsed =
            DateTime.tryParse('${c['date']} ${c['time']}'.replaceAll('/', '-'));
        return parsed != null && parsed.isAfter(now);
      } catch (_) {
        return true;
      }
    }).toList();

    final past = coaching.where((c) => !upcoming.contains(c)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (upcoming.isNotEmpty) ...[
          const Text('Upcoming Sessions',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...upcoming.map((c) => _CoachingCard(session: c)),
        ],
        if (past.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('Past Sessions',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...past.take(5).map((c) => _CoachingCard(session: c, isPast: true)),
        ],
      ],
    );
  }
}

class _CoachingCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final bool isPast;

  const _CoachingCard({required this.session, this.isPast = false});

  @override
  Widget build(BuildContext context) {
    final color = isPast ? Colors.white24 : const Color(0xFF6C63FF);
    final spots = session['spots'];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(isPast ? 0.15 : 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.school_rounded, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session['topic'] ?? 'Coaching Session',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                    Text(
                      'by ${session['coach'] ?? 'TBD'}',
                      style: TextStyle(color: color, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(session['date'] ?? '',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                  Text(session['time'] ?? '',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _ScrimChip(
                  icon: Icons.military_tech,
                  label: session['rank'] ?? 'All ranks'),
              const SizedBox(width: 8),
              if (spots != null)
                _ScrimChip(icon: Icons.people, label: '$spots spots'),
            ],
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  const _TabButton(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap,
      this.badge = 0});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF6C63FF) : const Color(0xFF1E1E2A),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16, color: selected ? Colors.white : Colors.white54),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: selected ? Colors.white : Colors.white54,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
              if (badge > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFF6B6B),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('$badge',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrimCard extends StatelessWidget {
  final Map<String, dynamic> scrim;
  final Color statusColor;
  final bool isPast;

  const _ScrimCard(
      {required this.scrim, required this.statusColor, this.isPast = false});

  @override
  Widget build(BuildContext context) {
    final status = scrim['status'] ?? 'open';
    final spots = scrim['spots'];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isPast ? Colors.white12 : statusColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.sports_esports, color: statusColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(scrim['format'] ?? 'Scrim',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    Text('${scrim['date']} at ${scrim['time']}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(status[0].toUpperCase() + status.substring(1),
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _ScrimChip(
                  icon: Icons.military_tech,
                  label: scrim['rank'] ?? 'All ranks'),
              const SizedBox(width: 8),
              if (spots != null)
                _ScrimChip(icon: Icons.people, label: '$spots spots'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScrimChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ScrimChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white54),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
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
  late Future<List<dynamic>> _leaderboard;
  bool _showLeaderboard = false;

  @override
  void initState() {
    super.initState();
    _leaderboard = _fetchLeaderboard();
  }

  Future<List<dynamic>> _fetchLeaderboard() async {
    final response = await http.get(
      Uri.parse('${Config.baseUrl}/api/leaderboard'),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load stats');
  }

  int _getLevel(int xp) => (0.1 * sqrt(xp.toDouble())).floor();
  int _xpForNextLevel(int level) => pow((level + 1) / 0.1, 2).toInt();
  int _xpForLevel(int level) => pow(level / 0.1, 2).toInt();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stats'),
        backgroundColor: const Color(0xFF12121A),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _leaderboard = _fetchLeaderboard()),
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _leaderboard,
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
                  const Text('Failed to load stats',
                      style: TextStyle(color: Colors.white54)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () =>
                        setState(() => _leaderboard = _fetchLeaderboard()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final leaderboard = snapshot.data!;
          final myEntry = leaderboard.firstWhere(
            (e) => e['userId'] == widget.user.id,
            orElse: () => null,
          );
          final myRank = myEntry != null ? leaderboard.indexOf(myEntry) + 1 : 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // My stats card
                if (myEntry != null) ...[
                  _buildMyStatsCard(myEntry, myRank),
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
                        color: const Color(0xFF6C63FF).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.leaderboard,
                            color: Color(0xFF6C63FF), size: 22),
                        const SizedBox(width: 12),
                        const Text('Leaderboard',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
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
                  ...leaderboard.take(10).toList().asMap().entries.map((entry) {
                    final rank = entry.key + 1;
                    final item = entry.value;
                    final xp = item['xp'] as int;
                    final level = _getLevel(xp);
                    final isMe = item['userId'] == widget.user.id;
                    final username = item['username'] ?? 'Unknown';
                    final avatar = item['avatar'];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isMe
                            ? const Color(0xFF6C63FF).withOpacity(0.15)
                            : const Color(0xFF12121A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isMe
                              ? const Color(0xFF6C63FF).withOpacity(0.5)
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
                                  color: Colors.white54, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(width: 8),
                          CircleAvatar(
                            radius: 16,
                            backgroundImage:
                                avatar != null ? NetworkImage(avatar) : null,
                            backgroundColor: const Color(0xFF6C63FF),
                            child: avatar == null
                                ? Text(username[0].toUpperCase(),
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12))
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  username,
                                  style: TextStyle(
                                    color: isMe
                                        ? const Color(0xFF6C63FF)
                                        : Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text('Level $level • $xp XP',
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 12)),
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

  Widget _buildMyStatsCard(dynamic stats, int rank) {
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
                    ? Text(widget.user.username[0].toUpperCase(),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 22))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.user.nickname,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    Text('Rank #$rank on the server',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Level $level',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$xp XP',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text('$nextLevelXp XP for Level ${level + 1}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
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
                    color: const Color(0xFF6C63FF).withOpacity(0.2),
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
    _loadUserRoles();
  }

  Future<void> _loadUserRoles() async {
    setState(() => _rolesLoading = true);
    try {
      // In a real app, load roles from backend using widget.user.id
      setState(() => _userRoles = Set<String>.from(widget.user.roles));
    } catch (_) {
      // keep defaults
    } finally {
      setState(() => _rolesLoading = false);
    }
  }

  Future<void> _toggleRole(String roleId, bool enabled) async {
    setState(() => _rolesLoading = true);
    try {
      final response = await http.post(
        Uri.parse(Config.manageRolesEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': widget.user.id,
          'roleId': roleId,
          'action': enabled ? 'add' : 'remove',
          'accessToken': widget.user.accessToken,
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          if (enabled) {
            _userRoles.add(roleId);
          } else {
            _userRoles.remove(roleId);
          }
        });
      } else {
        throw Exception('Failed to update role');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _rolesLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF12121A),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () => FeedbackSystem.showBugReportDialog(context,
                user: widget.user, currentScreen: 'Settings'),
          ),
          IconButton(
            icon: const Icon(Icons.feedback_outlined),
            onPressed: () =>
                FeedbackSystem.showFeedbackDialog(context, user: widget.user),
          ),
        ],
      ),
      body: _rolesLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Account section
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12121A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundImage: widget.user.avatar != null
                            ? NetworkImage(widget.user.avatar!)
                            : null,
                        backgroundColor: const Color(0xFF6C63FF),
                        child: widget.user.avatar == null
                            ? Text(widget.user.username[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white))
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.user.nickname,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            Text('@${widget.user.username}',
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: widget.onLogout,
                        icon: const Icon(Icons.logout),
                        label: const Text('Logout'),
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Appearance
                const _SectionHeader('Appearance'),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12121A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.dark_mode, color: Colors.white70),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Dark Mode',
                            style: TextStyle(color: Colors.white)),
                      ),
                      Switch(
                        value: _isDarkMode,
                        onChanged: (v) {
                          setState(() => _isDarkMode = v);
                          FusionApp.of(context)?.setThemeMode(
                              v ? ThemeMode.dark : ThemeMode.light);
                        },
                      )
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Notifications
                const _SectionHeader('Notifications'),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12121A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_active,
                          color: Colors.white70),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Enable Notifications',
                            style: TextStyle(color: Colors.white)),
                      ),
                      Switch(
                        value: _notificationsEnabled,
                        onChanged: (v) =>
                            setState(() => _notificationsEnabled = v),
                      )
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Roles
                const _SectionHeader('Roles'),
                _buildRolesSection(),

                const SizedBox(height: 24),

                // About
                const _SectionHeader('About'),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12121A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${Config.appName} • ${Config.appBuild}',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Version ${Config.appVersion}',
                          style: TextStyle(
                              color: Colors.white54, fontSize: 12)),
                      SizedBox(height: 8),
                      Text(Config.copyright,
                          style: TextStyle(
                              color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildRolesSection() {
    // Group roles by category for display
    final rolesByCategory =
        <String, List<MapEntry<String, Map<String, dynamic>>>>{};
    for (final entry in _availableRoles.entries) {
      final category = entry.value['category'] as String;
      rolesByCategory.putIfAbsent(category, () => []).add(entry);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rolesByCategory.entries.map((cat) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 8),
              child: Text(cat.key,
                  style: const TextStyle(
                      color: Colors.white70, fontWeight: FontWeight.bold)),
            ),
            ...cat.value.map((entry) {
              final roleId = entry.key;
              final role = entry.value;
              final color = role['color'] as Color;
              final enabled = _userRoles.contains(roleId);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF12121A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: color.withOpacity(0.8),
                          shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(role['name'] as String,
                          style: const TextStyle(color: Colors.white)),
                    ),
                    Switch(
                      value: enabled,
                      onChanged: (v) => _toggleRole(roleId, v),
                      activeThumbColor: color,
                    )
                  ],
                ),
              );
            })
          ],
        );
      }).toList(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}
