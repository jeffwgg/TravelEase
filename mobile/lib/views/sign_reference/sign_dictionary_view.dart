import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/entities/sign_language_entity.dart';
import '../../models/entities/sign_phrase_entity.dart';
import '../../models/repositories/feature_usage_repository.dart';
import '../../services/app_tour_controller.dart';
import '../../viewmodels/sign_dictionary_viewmodel.dart';
import '../../widgets/app_tour_coachmark.dart';
import 'sign_media_viewer_view.dart';
import 'favorite_phrases_view.dart';

class SignDictionaryView extends StatefulWidget {
  const SignDictionaryView({super.key});

  @override
  State<SignDictionaryView> createState() => _SignDictionaryViewState();
}

class _SignDictionaryViewState extends State<SignDictionaryView> {
  late final SignDictionaryViewModel _viewModel;
  final _searchController = TextEditingController();
  final _tourTargetKey = GlobalKey();
  final _categoryTourKey = GlobalKey();
  final _resultsTourKey = GlobalKey();
  int _tourStep = 0;

  final _categories = const [
    _CategoryItem('all', 'All', Icons.grid_view),
    _CategoryItem('airport', 'Airport', Icons.flight_takeoff),
    _CategoryItem('hotel', 'Hotel', Icons.hotel),
    _CategoryItem('restaurant', 'Food & Dining', Icons.restaurant),
    _CategoryItem('transit', 'Transit', Icons.directions_bus),
    _CategoryItem('medical', 'Medical', Icons.local_hospital),
    _CategoryItem('emergency', 'Emergency', Icons.warning_amber),
    _CategoryItem('animal', 'Animals', Icons.pets),
    _CategoryItem('general', 'General', Icons.chat_bubble_outline),
  ];

  @override
  void initState() {
    super.initState();
    _viewModel = SignDictionaryViewModel();
    FeatureUsageTracker.instance.opened(TrackedFeature.signDictionary);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Scaffold(
              appBar: AppBar(
                title: const Text('Sign Dictionary'),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(
                      Icons.star_rounded,
                      color: AppColors.secondary,
                    ),
                    tooltip: 'Bookmarked Favorites',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => const FavoritePhrasesView(),
                        ),
                      ).then((_) => _viewModel.loadDictionary());
                    },
                  ),
                ],
              ),
              body: Column(
                children: [
                  // Search Bar (FR-M4-13)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Column(
                      children: [
                        TextField(
                          key: _tourTargetKey,
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText:
                                'Search sign phrases, gloss, or keywords...',
                            prefixIcon: const Icon(
                              Icons.search,
                              color: AppColors.textMuted,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      _viewModel.search('');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: AppColors.surfaceVariant,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (q) => _viewModel.search(q),
                        ),
                      ],
                    ),
                  ),

                  // Categories Horizontal Selector (FR-M4-14)
                  SizedBox(
                    key: _categoryTourKey,
                    height: 52,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      itemCount: _categories.length,
                      itemBuilder: (context, i) {
                        final cat = _categories[i];
                        final selected = cat.id == _viewModel.selectedCategory;
                        return GestureDetector(
                          onTap: () => _viewModel.selectCategory(cat.id),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  cat.icon,
                                  size: 16,
                                  color: selected
                                      ? Colors.white
                                      : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  cat.name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: selected
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Sign Dialect Selector Tabs - FR-M4-01: toggle between BIM / ASL visual assets
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        ...const [
                          SignLanguageType.bim,
                          SignLanguageType.asl,
                        ].map((lang) {
                          final isSelected = _viewModel.selectedDialect == lang;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => _viewModel.switchDialect(lang),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary.withValues(
                                          alpha: 0.12,
                                        )
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.cardBorder,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      lang.flagEmoji,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${lang.code} (${lang.countryCode})',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected
                                            ? AppColors.primary
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        const Spacer(),
                        Text(
                          '${_viewModel.phrases.length} signs',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Phrases List with Gloss Notations (FR-M4-02, FR-M4-04)
                  Expanded(
                    child: KeyedSubtree(
                      key: _resultsTourKey,
                      child: _viewModel.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _viewModel.phrases.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.search_off_rounded,
                                    size: 54,
                                    color: AppColors.textMuted.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text('No matching sign phrases found'),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Try another keyword or category filter',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              itemCount: _viewModel.phrases.length,
                              itemBuilder: (context, i) =>
                                  _buildPhraseCard(_viewModel.phrases[i]),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: AppTourCoachmark(
                feature: AppTourFeature.signDictionary,
                targetKey: switch (_tourStep) {
                  0 => _tourTargetKey,
                  1 => _categoryTourKey,
                  _ => _resultsTourKey,
                },
                title: switch (_tourStep) {
                  0 => 'Search signs',
                  1 => 'Choose a method',
                  _ => 'View results',
                },
                message: switch (_tourStep) {
                  0 => 'Enter a phrase, gloss, or keyword here.',
                  1 => 'Filter by category, then choose BIM or ASL.',
                  _ => 'Matching signs and phrases appear here.',
                },
                onNext: _advanceTour,
              ),
            ),
          ],
        );
      },
    );
  }

  void _advanceTour() {
    if (_tourStep < 2) {
      setState(() => _tourStep++);
    } else {
      AppTourController.instance.advance(context);
    }
  }

  Widget _buildPhraseCard(SignPhrase phrase) {
    final isFav = _viewModel.isFavorite(phrase.id);
    final gloss = phrase.getGloss(_viewModel.selectedDialect);
    final dialect = _viewModel.selectedDialect;
    final primaryText = phrase.getPrimaryText(dialect);
    final secondaryText = dialect == SignLanguageType.bim
        ? phrase.phraseEn
        : phrase.phraseMs;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => SignMediaViewerView(
                phrase: phrase,
                initialDialect: _viewModel.selectedDialect,
              ),
            ),
          );
          // The viewer's star button edits the same favorites list — refresh
          // it so the dictionary reflects the change without a re-enter.
          _viewModel.refreshFavorites();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.sign_language_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      primaryText,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      secondaryText,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Gloss: $gloss',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            phrase.categoryId.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: isFav ? AppColors.secondary : AppColors.textMuted,
                  size: 24,
                ),
                onPressed: () => _viewModel.toggleFavorite(phrase.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryItem {
  final String id;
  final String name;
  final IconData icon;
  const _CategoryItem(this.id, this.name, this.icon);
}
