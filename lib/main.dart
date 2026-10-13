import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:novel_app/route_observer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/app_theme_mode.dart';
import 'screens/main_screen.dart';
import 'platforms/windows/windows_main_screen.dart';
import 'offline/service/offline_mode_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Khôi phục trạng thái Offline, mặc định là false.
  await OfflineModeService.initialize();

  final prefs = await SharedPreferences.getInstance();
  await OfflineModeService.initialize();
  final index = prefs.getInt('themeMode') ?? 2;

  final safeIndex =
  index >= 0 && index < AppThemeMode.values.length ? index : 2;

  runApp(
    MyApp(initialMode: AppThemeMode.values[safeIndex]),
  );
}

class MyApp extends StatefulWidget {
  final AppThemeMode initialMode;

  const MyApp({
    super.key,
    required this.initialMode,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late AppThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialMode;
  }

  Future<void> _saveTheme(AppThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
  }

  void _changeTheme(AppThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });

    _saveTheme(mode);
  }

  ThemeMode get _flutterThemeMode {
    switch (_themeMode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  Widget _buildPlatformHome() {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return WindowsMainScreen(
        currentMode: _themeMode,
        onThemeChanged: _changeTheme,
      );
    }

    return MainScreen(
      currentMode: _themeMode,
      onThemeChanged: _changeTheme,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [routeObserver],
      debugShowCheckedModeBanner: false,
      themeMode: _flutterThemeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        cardColor: const Color(0xFF1E1E1E),
        colorScheme: const ColorScheme.dark(
          primary: Colors.blueAccent,
          surface: Color(0xFF1E1E1E),
          onSurface: Colors.white70,
          secondary: Colors.grey,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFFE0E0E0)),
          bodyMedium: TextStyle(color: Color(0xFFBDBDBD)),
        ),
      ),
      home: _buildPlatformHome(),
    );
  }
}