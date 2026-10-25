import 'package:flutter/material.dart';
import '../../models/app_theme_mode.dart';
import '../../screens/home_screen.dart';
import '../../screens/library_screen.dart';
import '../../screens/profile_screen.dart';
class WindowsMainScreen extends StatefulWidget {
  final AppThemeMode currentMode;
  final ValueChanged<AppThemeMode> onThemeChanged;
  const WindowsMainScreen({
    super.key,
    required this.currentMode,
    required this.onThemeChanged,
  });
  @override
  State<WindowsMainScreen> createState() => _WindowsMainScreenState();
}
class _WindowsMainScreenState extends State<WindowsMainScreen> {
  int _selectedIndex = 0;
  late final List<Widget> _pages = [
    const HomePage(),
    const LibraryPage(),
    ProfilePage(
      currentMode: widget.currentMode,
      onThemeChanged: widget.onThemeChanged,
    ),
  ];
  @override
  void didUpdateWidget(covariant WindowsMainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentMode != widget.currentMode ||
        oldWidget.onThemeChanged != widget.onThemeChanged) {
      _pages[2] = ProfilePage(
        currentMode: widget.currentMode,
        onThemeChanged: widget.onThemeChanged,
      );
    }
  }
  static const List<_NavigationItem> _navigationItems = [
    _NavigationItem(
      label: 'Trang chủ',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
    ),
    _NavigationItem(
      label: 'Library',
      icon: Icons.book_outlined,
      selectedIcon: Icons.book,
    ),
    _NavigationItem(
      label: 'Other',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
    ),
  ];
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            Container(
              width: 224,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  right: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 24, 16, 28),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.menu_book_rounded,
                            color: colorScheme.onPrimaryContainer,
                            size: 25,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Cạk Cạk Cạk',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
                    child: Text(
                      'THƯ VIỆN',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (int index = 0;
                  index < _navigationItems.length;
                  index++)
                    _buildNavigationItem(
                      context,
                      index,
                      _navigationItems[index],
                    )
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 64,
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      border: Border(
                        bottom: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _navigationItems[_selectedIndex].label,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.desktop_windows_outlined,
                          color: colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Windows',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _pages[_selectedIndex],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildNavigationItem(
      BuildContext context,
      int index,
      _NavigationItem item,
      ) {
    final theme = Theme.of(context);
    final selected = _selectedIndex == index;
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected
            ? colorScheme.secondaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (_selectedIndex != index) {
              setState(() {
                _selectedIndex = index;
              });
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 13,
            ),
            child: Row(
              children: [
                Icon(
                  selected ? item.selectedIcon : item.icon,
                  size: 22,
                  color: selected
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                      color: selected
                          ? colorScheme.onSecondaryContainer
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
class _NavigationItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  const _NavigationItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}
