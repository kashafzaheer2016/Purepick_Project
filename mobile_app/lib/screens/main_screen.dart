import 'package:flutter/material.dart';
import '../design/pp.dart';
import 'home_screen.dart';
import 'history_screen.dart';
import 'saved_screen.dart';
import 'ai_chat_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const HistoryScreen(isTab: true),
    const SavedScreen(isTab: true),
    const AiChatScreen(isTab: true),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: _currentIndex == 0, // only allow pop if on home tab
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0); // go back to home tab instead of exiting
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1015) : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildNavItem(0, Icons.home_outlined, Icons.home, 'Home'),
                  _buildNavItem(1, Icons.history_outlined, Icons.history, 'History'),
                  _buildNavItem(2, Icons.bookmark_outline, Icons.bookmark, 'Saved'),
                  _buildNavItem(3, Icons.chat_outlined, Icons.chat, 'AI Chat'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon, String label) {
    final isSelected = _currentIndex == index;
    final theme = Theme.of(context);
    final color = isSelected ? PP.rose : (theme.brightness == Brightness.dark ? Colors.white38 : PP.muted);

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? PP.rose.withOpacity(0.1) : Colors.transparent,
          borderRadius: PP.pill,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isSelected ? activeIcon : icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: PP.label(10, color: color, weight: isSelected ? FontWeight.w600 : FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }
}
