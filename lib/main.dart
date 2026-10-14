import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:novel_app/route_observer.dart';
import 'package:novel_app/services/app_preference.dart';

import 'models/app_theme_mode.dart';
import 'offline/service/offline_mode_service.dart';
import 'platforms/windows/windows_main_screen.dart';
import 'platforms/windows/windows_storage_manager.dart';
import 'platforms/windows/windows_storage_setup_screen.dart';
import 'screens/main_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Windows phải cấu hình thư mục lưu trữ trước khi khởi chạy.
  if (WindowsStorageManager.isWindows) {
    final root = await WindowsStorageManager.loadConfiguredRoot();

    if (root == null) {
      runApp(WindowsStorageBootstrapApp(onConfigured: _launchConfiguredApp));
      return;
    }
  }

  await _launchConfiguredApp();
}

/// Khởi chạy ứng dụng sau khi thư mục lưu trữ đã hợp lệ.
Future<void> _launchConfiguredApp() async {
  await OfflineModeService.initialize();

  final prefs = await AppPreferences.getInstance();
  final index = prefs.getInt('themeMode') ?? 2;

  final safeIndex = index >= 0 && index < AppThemeMode.values.length
      ? index
      : 2;

  runApp(MyApp(initialMode: AppThemeMode.values[safeIndex]));
}

/// Ứng dụng tạm thời chỉ hiển thị màn hình chọn thư mục trên Windows.
class WindowsStorageBootstrapApp extends StatelessWidget {
  final Future<void> Function() onConfigured;

  const WindowsStorageBootstrapApp({super.key, required this.onConfigured});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Novel App',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      ),
      home: WindowsStorageSetupScreen(onConfigured: onConfigured),
    );
  }
}

class MyApp extends StatefulWidget {
  final AppThemeMode initialMode;

  const MyApp({super.key, required this.initialMode});

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
    final prefs = await AppPreferences.getInstance();
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

    return MainScreen(currentMode: _themeMode, onThemeChanged: _changeTheme);
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
