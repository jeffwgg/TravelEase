import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';

class HomeView extends StatefulWidget {
  final Widget child;
  const HomeView({super.key, required this.child});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  int _currentIndex = 0;

  static const _tabs = [
    '/home',
    '/communicate',
    '/assistance-request',
    '/profile',
  ];

  @override
  Widget build(BuildContext context) {
    // Sync index with current location
    final location = GoRouterState.of(context).uri.toString();
    for (int i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i])) {
        _currentIndex = i;
        break;
      }
    }

    return Scaffold(
      body: widget.child,
      floatingActionButton: const _SosFloatingButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(Icons.explore_rounded, 'Explore', 0),
                _buildNavItem(Icons.forum_outlined, 'Communicate', 1),
                // Middle Sign Language Camera Translation Button
                _buildSignTranslateButton(context),
                _buildNavItem(Icons.support_agent_rounded, 'Assistance', 2),
                _buildNavItem(Icons.person_rounded, 'Profile', 3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _currentIndex = index);
        context.go(_tabs[index]);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? AppColors.primary : AppColors.textMuted,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignTranslateButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        context.push('/sign-camera');
      },
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, Color(0xFF0F766E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sign_language_rounded, color: Colors.white, size: 24),
            SizedBox(height: 2),
            Text(
              'Translate',
              style: TextStyle(
                color: Colors.white,
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SosFloatingButton extends StatefulWidget {
  const _SosFloatingButton();

  @override
  State<_SosFloatingButton> createState() => _SosFloatingButtonState();
}

class _SosFloatingButtonState extends State<_SosFloatingButton> {
  static const _holdDuration = Duration(milliseconds: 1200);
  Timer? _holdTimer;
  bool _activated = false;

  void _startHold(TapDownDetails _) {
    _holdTimer?.cancel();
    _activated = false;
    _holdTimer = Timer(_holdDuration, () {
      if (!mounted) return;
      _activated = true;
      context.push('/sos-countdown');
    });
  }

  void _finishTap(TapUpDetails _) {
    _holdTimer?.cancel();
    if (_activated) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Hold to activate SOS'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _cancelHold() {
    _holdTimer?.cancel();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Emergency SOS. Hold for 1.2 seconds to activate.',
      child: GestureDetector(
        onTapDown: _startHold,
        onTapUp: _finishTap,
        onTapCancel: _cancelHold,
        child: Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            color: AppColors.emergency,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: AppColors.emergency.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sos_rounded, color: Colors.white, size: 27),
              Text(
                'HOLD',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
