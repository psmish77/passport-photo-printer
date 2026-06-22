import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
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
  
  runApp(const PanditjiApp());
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
        toolbarHeight: 60.0,
        centerTitle: true,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.printer, size: 22, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text(
              'Passport Photo Printer',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
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
