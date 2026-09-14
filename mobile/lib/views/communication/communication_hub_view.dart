import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../models/entities/sign_language_entity.dart';
import '../sign_reference/sign_dictionary_view.dart';
import '../sign_reference/favorite_phrases_view.dart';
import 'two_way_dialogue_view.dart';

class CommunicationHubView extends StatelessWidget {
  const CommunicationHubView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accessible Communication Tools'),
        automaticallyImplyLeading: false,
        // The Emergency SOS entry lives in Profile, and the temporary speech
        // diagnostics screen has been removed — no header actions here.
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

            // 2 x 2 grid of Communication Tools
            Row(
              children: [
                Expanded(
                  child: _buildToolCard(
                    context: context,
                    icon: Icons.sign_language_rounded,
                    title: 'Live Camera Sign Translation',
                    subtitle: 'Real-time gesture AI with Auto-Speak',
                    accentColor: AppColors.primary,
                    onTap: () => context.push('/sign-camera'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildToolCard(
                    context: context,
                    icon: Icons.chat_bubble_outline_rounded,
                    title: '2-Way Dialogue',
                    subtitle: 'Counter split-screen chat',
                    accentColor: AppColors.secondary,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (ctx) => const TwoWayDialogueView()),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildToolCard(
                    context: context,
                    icon: Icons.menu_book_rounded,
                    title: 'Sign Dictionary',
                    subtitle: 'BIM / ASL Library',
                    accentColor: const Color(0xFF10B981),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (ctx) => const SignDictionaryView()),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildToolCard(
                    context: context,
                    icon: Icons.star_rounded,
                    title: 'Favorites',
                    subtitle: 'Bookmarked quick phrases',
                    accentColor: AppColors.secondary,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (ctx) => const FavoritePhrasesView()),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Quick Travel Dialect Badges
            Text(
              'Supported Sign Dialects',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [SignLanguageType.bim, SignLanguageType.asl].map((lang) {
                  return Container(
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
                        Text(lang.flagEmoji, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(lang.code, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                            Text(lang.countryName, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildToolCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        // Fixed height so every card in the grid is the same size even when
        // one title/subtitle wraps to extra lines.
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
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accentColor, size: 24),
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
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
