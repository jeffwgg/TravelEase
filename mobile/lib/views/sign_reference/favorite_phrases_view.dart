import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/entities/favorite_phrase_entity.dart';
import '../../viewmodels/favorite_phrases_viewmodel.dart';
import 'sign_media_viewer_view.dart';

class FavoritePhrasesView extends StatefulWidget {
  const FavoritePhrasesView({super.key});

  @override
  State<FavoritePhrasesView> createState() => _FavoritePhrasesViewState();
}

class _FavoritePhrasesViewState extends State<FavoritePhrasesView> {
  late final FavoritePhrasesViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = FavoritePhrasesViewModel();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  void _onRemove(FavoritePhrase fav) {
    _viewModel.removeFavorite(fav);
    final messenger = ScaffoldMessenger.of(context);
    // Drop any leftover bar first: without this, back-to-back removals
    // queue up and the message looks like it never goes away.
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Removed "${fav.phrase?.phraseEn ?? 'Phrase'}" from favorites'),
        duration: const Duration(seconds: 3),
        // Flutter >=3.35: a SnackBar with an action defaults to `persist`
        // (never auto-dismisses) unless told otherwise — the Undo action was
        // making this bar stick forever.
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _viewModel.restoreFavorite(fav),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bookmarked Favorites'),
                // Whose list this is: the signed-in account, or the local
                // demo bucket while signed out.
                Text(
                  _viewModel.accountLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: _viewModel.isLoading
              ? const Center(child: CircularProgressIndicator())
              : _viewModel.favorites.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_border_rounded, size: 64, color: AppColors.textMuted.withValues(alpha: 0.3)),
                          const SizedBox(height: 16),
                          Text('No bookmarked phrases yet', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text('Star phrases from the Sign Dictionary for fast counter access', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          color: AppColors.surfaceVariant,
                          child: Row(
                            children: [
                              const Icon(Icons.drag_indicator, size: 16, color: AppColors.textMuted),
                              const SizedBox(width: 6),
                              Text('Drag and reorder phrases for priority quick-access', style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ReorderableListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _viewModel.favorites.length,
                            onReorder: (oldIndex, newIndex) => _viewModel.reorder(oldIndex, newIndex),
                            itemBuilder: (context, i) {
                              final fav = _viewModel.favorites[i];
                              final phrase = fav.phrase;
                              return Card(
                                key: ValueKey(fav.id),
                                margin: const EdgeInsets.only(bottom: 10),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: const BorderSide(color: AppColors.cardBorder),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  leading: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: AppColors.secondary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.star_rounded, color: AppColors.secondary, size: 24),
                                  ),
                                  title: Text(
                                    phrase?.phraseEn ?? 'Sign Phrase',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    phrase?.phraseMs ?? 'Frasa Isyarat',
                                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.play_circle_fill, color: AppColors.primary, size: 28),
                                        tooltip: 'Watch Sign Video',
                                        onPressed: () async {
                                          if (phrase == null) return;
                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (ctx) => SignMediaViewerView(phrase: phrase),
                                            ),
                                          );
                                          // The viewer can un-star this phrase.
                                          _viewModel.loadFavorites();
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: AppColors.textMuted, size: 20),
                                        tooltip: 'Remove from Favorites',
                                        onPressed: () => _onRemove(fav),
                                      ),
                                      ReorderableDragStartListener(
                                        index: i,
                                        child: const Padding(
                                          padding: EdgeInsets.only(left: 4),
                                          child: Icon(Icons.drag_handle, color: AppColors.textMuted, size: 22),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
        );
      },
    );
  }
}
