import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/repositories/feature_usage_repository.dart';

class SosCountdownView extends StatefulWidget {
  const SosCountdownView({super.key});

  @override
  State<SosCountdownView> createState() => _SosCountdownViewState();
}

class _SosCountdownViewState extends State<SosCountdownView> {
  static const _countdownDuration = 3;
  Timer? _timer;
  int _secondsRemaining = _countdownDuration;

  @override
  void initState() {
    super.initState();
    FeatureUsageTracker.instance.opened(TrackedFeature.sos);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsRemaining == 1) {
        _timer?.cancel();
        context.go('/sos-active');
        return;
      }
      setState(() => _secondsRemaining--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _cancel() {
    _timer?.cancel();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF7F7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.emergency.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.sos_rounded,
                  size: 48,
                  color: AppColors.emergency,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Emergency SOS',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: AppColors.emergency,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Sending emergency alert in',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Text(
                  '$_secondsRemaining',
                  key: ValueKey(_secondsRemaining),
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    color: AppColors.emergency,
                    fontSize: 96,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _cancel,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('CANCEL SOS'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.emergency,
                    side: const BorderSide(
                      color: AppColors.emergency,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'Cancel before the countdown ends to stop the alert.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
