import 'package:flutter/material.dart';
import '../../core/theme.dart';

class FavoritePhrasesView extends StatelessWidget {
  const FavoritePhrasesView({super.key});

  @override
  Widget build(BuildContext context) {
    final favorites = [
      const _Fav('Hello / Greeting', Icons.waving_hand_outlined, 'General'),
      const _Fav('Thank you', Icons.volunteer_activism_outlined, 'General'),
      const _Fav('Where is the gate?', Icons.flight_takeoff_outlined, 'Airport'),
      const _Fav('I need help', Icons.sos_outlined, 'Emergency'),
      const _Fav('How much does it cost?', Icons.payments_outlined, 'General'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorite Phrases'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: favorites.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.favorite_border, size: 64, color: AppColors.textMuted.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text('No favorites yet', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textMuted)),
                  const SizedBox(height: 8),
                  Text('Bookmark phrases from the Sign Dictionary', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: favorites.length,
              onReorder: (oldIndex, newIndex) {},
              itemBuilder: (context, i) {
                final fav = favorites[i];
                return Card(
                  key: ValueKey(fav.text),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Icon(fav.icon, color: AppColors.primary, size: 22),
                    ),
                    title: Text(fav.text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(fav.category, style: Theme.of(context).textTheme.bodySmall),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: const Icon(Icons.play_circle, color: AppColors.primary, size: 24), onPressed: () {}),
                        const Icon(Icons.drag_handle, color: AppColors.textMuted, size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _Fav {
  final String text;
  final IconData icon;
  final String category;
  const _Fav(this.text, this.icon, this.category);
}
