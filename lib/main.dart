import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:http/http.dart' as http;
import 'dart:js' as js;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'screens/passport_tool.dart';
import 'screens/id_card_tool.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Try loading the physical .env configuration
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Warning: No .env configuration found. Defaulting to empty.");
  }

  // Auto-sync API key from Vercel config silently on every startup
  _autoSyncApiKey();
  
  runApp(const PanditjiApp());
}

/// Silently fetches the latest remove.bg API key from the Vercel config endpoint
/// and stores it in SharedPreferences — no UI interaction required.
Future<void> _autoSyncApiKey() async {
  try {
    final response = await http.get(
      Uri.parse('https://panditji-printing-panditjihotel.vercel.app/config.json'),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final cloudKey = data['remove_bg_api_key']?.toString() ?? '';
      if (cloudKey.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('REMOVE_BG_API_KEY', cloudKey);
        debugPrint("API key auto-synced from Vercel.");
      }
    }
  } catch (e) {
    debugPrint("Auto-sync skipped (no internet or timeout): $e");
  }
}


class PanditjiApp extends StatefulWidget {
  const PanditjiApp({super.key});

  @override
  State<PanditjiApp> createState() => _PanditjiAppState();
}

class _PanditjiAppState extends State<PanditjiApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDark') ?? false;
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  void _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final newMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    await prefs.setBool('isDark', newMode == ThemeMode.dark);
    setState(() {
      _themeMode = newMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Elegant Minimalist Studio Theme Configuration
    final ColorScheme lightScheme = ColorScheme.fromSeed(
      seedColor: Colors.black,
      primary: Colors.black,
      secondary: Colors.grey.shade800,
      surface: const Color(0xFFFAFAFA),
      onPrimary: Colors.white,
      brightness: Brightness.light,
    );

    final ColorScheme darkScheme = ColorScheme.fromSeed(
      seedColor: Colors.white,
      primary: Colors.white,
      secondary: Colors.grey.shade300,
      surface: const Color(0xFF18181B),
      onPrimary: Colors.black,
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'Panditji Printing Services',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        fontFamily: 'Outfit',
        useMaterial3: true,
        colorScheme: lightScheme,
        scaffoldBackgroundColor: lightScheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: lightScheme.surface,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      darkTheme: ThemeData(
        fontFamily: 'Outfit',
        useMaterial3: true,
        colorScheme: darkScheme,
        scaffoldBackgroundColor: darkScheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: darkScheme.surface,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: MainNavigation(toggleTheme: _toggleTheme),
    );
  }
}

class MainNavigation extends StatefulWidget {
  final VoidCallback toggleTheme;
  const MainNavigation({super.key, required this.toggleTheme});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const PassportToolScreen(),
    const IdCardToolScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 85.0,
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.printer, size: 24, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Panditji Hotel',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
                ),
              ],
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () {
                const url = 'https://maps.app.goo.gl/ziW4AX8jeZK4eED58';
                if (kIsWeb) {
                  js.context.callMethod('open', [url]);
                } else {
                  Clipboard.setData(const ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Map location link copied to clipboard!'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.map_pin,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary.withAlpha(200),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Ramtek road Mauda - View on Map',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary.withAlpha(200),
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(isDark ? LucideIcons.moon : LucideIcons.sun),
            onPressed: widget.toggleTheme,
          )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: _pages[_currentIndex],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(LucideIcons.camera),
            label: 'AutoPassport',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.scan_line),
            label: 'ID Maker',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
