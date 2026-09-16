import 'package:flutter/material.dart';

import '../services/app_tour_controller.dart';
import 'home_guidance_overlay.dart';

/// A feature-screen coach mark for the single TravelEase introduction.
class AppTourCoachmark extends StatelessWidget {
  const AppTourCoachmark({
    super.key,
    required this.feature,
    required this.targetKey,
    required this.title,
    required this.message,
    this.onNext,
  });

  final AppTourFeature feature;
  final GlobalKey targetKey;
  final String title;
  final String message;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppTourController.instance,
      builder: (context, _) {
        if (!AppTourController.instance.isShowing(feature)) {
          return const SizedBox.shrink();
        }

        void advance() {
          if (onNext != null) {
            onNext!();
          } else {
            AppTourController.instance.advance(context);
          }
        }

        return HomeGuidanceOverlay(
          targetKey: targetKey,
          title: title,
          message: message,
          skipLabel: 'Skip',
          onSkip: () => AppTourController.instance.confirmAndSkip(context),
          actions: [
            HomeGuidanceAction(
              label: 'Next',
              isPrimary: true,
              onPressed: advance,
            ),
          ],
        );
      },
    );
  }
}
