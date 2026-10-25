import 'package:flutter/material.dart';
import '../services/ota.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'profile_screen.dart';
import '../models/app_theme_mode.dart';
class MainScreen extends StatefulWidget {
  final AppThemeMode currentMode;
  final Function(AppThemeMode) onThemeChanged;
  const MainScreen({
    super.key,
    required this.currentMode,
    required this.onThemeChanged,
  });
  @override
  State<MainScreen> createState() => _MainScreenState();
}
class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  @override
  void initState(){
    super.initState();
    OtaService().cleanUpOldApk();
  }
  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomePage(),
      const LibraryPage(),
      ProfilePage(
        currentMode: widget.currentMode,
        onThemeChanged: widget.onThemeChanged,
      ),
    ];
    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.book_outlined),
            selectedIcon: Icon(Icons.book),
            label: 'Bookmarks',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Options',
          ),
        ],
      ),
    );
  }
}