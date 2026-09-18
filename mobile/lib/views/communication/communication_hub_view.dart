import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/entities/sign_language_entity.dart';
import '../../services/app_tour_controller.dart';
import '../../widgets/app_tour_coachmark.dart';
import '../sign_reference/favorite_phrases_view.dart';
import '../sign_reference/sign_dictionary_view.dart';

class CommunicationHubView extends StatelessWidget {
  const CommunicationHubView({super.key});

  static final _signTourKey = GlobalKey();
  static final _dialogueTourKey = GlobalKey();
  static final _dictionaryTourKey = GlobalKey();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Scaffold(
        appBar: AppBar(
          title: const Text('Accessible Communication Tools'),
          automaticallyImplyLeading: false,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Multimodal speech, live dialogue, and sign reference engines for travelers',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _toolCard(
                      context: context,
                      tourKey: _signTourKey,
                      icon: Icons.sign_language_rounded,
                      title: 'Live Camera Sign Translation',
                      subtitle: 'Real-time gesture AI with Auto-Speak',
                      color: AppColors.primary,
                      onTap: () => context.push('/sign-camera'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _toolCard(
                      context: context,
                      tourKey: _dialogueTourKey,
                      icon: Icons.chat_bubble_outline_rounded,
                      title: '2-Way Dialogue',
                      subtitle: 'Counter split-screen chat',
                      color: AppColors.secondary,
                      onTap: () => context.push('/dialogue'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _toolCard(
                      context: context,
                      tourKey: _dictionaryTourKey,
                      icon: Icons.menu_book_rounded,
                      title: 'Sign Dictionary',
                      subtitle: 'BIM / ASL Library',
                      color: const Color(0xFF10B981),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SignDictionaryView(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _toolCard(
                      context: context,
                      icon: Icons.star_rounded,
                      title: 'Favorites',
                      subtitle: 'Bookmarked quick phrases',
                      color: AppColors.secondary,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FavoritePhrasesView(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Supported Sign Dialects',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    SignLanguageType.bim,
                    SignLanguageType.asl,
                  ].map(_dialectBadge).toList(),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      _guide(
        AppTourFeature.communicationSignMenu,
        _signTourKey,
        'Sign Translate',
        'Choose Live Camera Sign Translation.',
      ),
      _guide(
        AppTourFeature.communicationDialogueMenu,
        _dialogueTourKey,
        'Two-Way Dialogue',
        'Choose this for a live conversation.',
      ),
      _guide(
        AppTourFeature.communicationDictionaryMenu,
        _dictionaryTourKey,
        'Sign Dictionary',
        'Choose this to look up signs and phrases.',
      ),
    ],
  );

  Widget _guide(
    AppTourFeature feature,
    GlobalKey targetKey,
    String title,
    String message,
  ) => Positioned.fill(
    child: AppTourCoachmark(
      feature: feature,
      targetKey: targetKey,
      title: title,
      message: message,
    ),
  );

  Widget _dialectBadge(SignLanguageType language) => Container(
    margin: const EdgeInsets.only(right: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(language.flagEmoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              language.code,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            Text(
              language.countryName,
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _toolCard({
    required BuildContext context,
    Key? tourKey,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) => InkWell(
    key: tourKey,
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      height: 152,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    ),
  );
}
