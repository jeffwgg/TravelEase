import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/app_tour_controller.dart';

class TourCompleteView extends StatelessWidget {
  const TourCompleteView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.celebration_outlined,
                    size: 46,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'You’re all set!',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                const Text(
                  'That’s the end of the guide. Have fun with TravelEase!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: () =>
                      AppTourController.instance.finishTour(context),
                  child: const Text('Start exploring'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
