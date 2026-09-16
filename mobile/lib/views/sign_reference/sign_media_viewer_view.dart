import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme.dart';
import '../../models/entities/sign_language_entity.dart';
import '../../models/entities/sign_phrase_entity.dart';
import '../../models/repositories/feature_usage_repository.dart';
import '../../viewmodels/sign_media_viewer_viewmodel.dart';

class SignMediaViewerView extends StatefulWidget {
  final SignPhrase? phrase;
  final SignLanguageType initialDialect;

  const SignMediaViewerView({
    super.key,
    this.phrase,
    this.initialDialect = SignLanguageType.bim,
  });

  @override
  State<SignMediaViewerView> createState() => _SignMediaViewerViewState();
}

class _SignMediaViewerViewState extends State<SignMediaViewerView> {
  late final SignMediaViewerViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = SignMediaViewerViewModel();
    if (widget.phrase != null) {
      _viewModel.initPhrase(
        phrase: widget.phrase!,
        initialDialect: widget.initialDialect,
      );
      FeatureUsageTracker.instance.completed(TrackedFeature.signDictionary);
    }
  }

  // FR-M4-12: immersive landscape full-screen playback
  void _toggleFullScreen() {
    _viewModel.toggleFullScreen();
    if (_viewModel.isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _viewModel.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        if (_viewModel.isFullScreen) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: Stack(
                children: [_buildVideoSurface(height: double.infinity)],
              ),
            ),
          );
        }

        final phrase = _viewModel.phrase;
        final dialect = _viewModel.currentDialect;
        if (phrase == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Sign Media Viewer')),
            body: const Center(child: Text('No sign phrase selected.')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text('${dialect.code} Media Viewer'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _viewModel.isFavorite
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: _viewModel.isFavorite
                      ? AppColors.secondary
                      : AppColors.textMuted,
                  size: 26,
                ),
                tooltip: _viewModel.isFavorite
                    ? 'Remove from Favorites'
                    : 'Add to Favorites',
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final added = await _viewModel.toggleFavorite();
                  messenger.showSnackBar(
                    SnackBar(
                      duration: const Duration(seconds: 2),
                      content: Text(
                        added ? 'Added to favorites' : 'Removed from favorites',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Real video player surface (FR-M4-05..12)
                _buildVideoSurface(height: 320),

                // Phrase Metadata & Multilingual Text
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // FR-M4-01: BIM / ASL visual asset toggle
                          ...const [
                            SignLanguageType.bim,
                            SignLanguageType.asl,
                          ].map((lang) {
                            final isSelected = dialect == lang;
                            return Flexible(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () => _viewModel.switchDialect(lang),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary.withValues(
                                            alpha: 0.12,
                                          )
                                        : AppColors.surfaceVariant,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.primaryLight
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        lang.flagEmoji,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          '${lang.displayName} (${lang.code})',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: isSelected
                                                ? AppColors.primary
                                                : AppColors.textMuted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${phrase.categoryId.toUpperCase()}  •  ${phrase.scenario ?? 'Travel Scenario'}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Selected dialect's language shown first (largest),
                      // each line with its own TTS speak button
                      ...phrase.orderedTextsWithLanguage(dialect).indexed.map((
                        e,
                      ) {
                        final (i, pair) = e;
                        final (text, lang) = pair;
                        final style = switch (i) {
                          0 => Theme.of(context).textTheme.headlineLarge,
                          1 =>
                            Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: AppColors.textSecondary),
                          _ => const TextStyle(
                            fontSize: 14,
                            color: AppColors.textMuted,
                          ),
                        };
                        final isSpeakingThis =
                            _viewModel.isSpeaking &&
                            _viewModel.speakingLang == lang;
                        return Padding(
                          padding: EdgeInsets.only(
                            top: i == 0
                                ? 0
                                : i == 1
                                ? 4
                                : 2,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(child: Text(text, style: style)),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                icon: isSpeakingThis
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.primary,
                                        ),
                                      )
                                    : Icon(
                                        Icons.volume_up_rounded,
                                        size: i == 0 ? 22 : 18,
                                        color: AppColors.primary,
                                      ),
                                tooltip: 'Play audio ($lang)',
                                onPressed: _viewModel.isSpeaking
                                    ? null
                                    : () => _viewModel.speakAloud(
                                        text: text,
                                        language: lang,
                                      ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 14),

                      // Gloss Code Box (FR-M4-02)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.code_rounded,
                              size: 18,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Written Gloss: ${phrase.getGloss(dialect)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppColors.accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Step-by-Step Hand and Body Descriptions (FR-M4-03)
                      Text(
                        'Step-by-Step Signing Guide',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: AppColors.cardBorder),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: phrase.stepInstructions.isNotEmpty
                                ? phrase.stepInstructions
                                      .map((step) => _buildStepItem(step))
                                      .toList()
                                : [
                                    _buildStepItem(
                                      const SignMovementStep(
                                        step: 1,
                                        title: 'Begin at Chest Level',
                                        description: 'Position both hands in front with neutral palms facing outward.',
                                      ),
                                    ),
                                    const Divider(height: 24),
                                    _buildStepItem(
                                      const SignMovementStep(
                                        step: 2,
                                        title: 'Complete Target Gesture',
                                        description: 'Execute the fluid sign movement matching the video playback.',
                                      ),
                                    ),
                                  ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoSurface({required double height}) {
    return Container(
      width: double.infinity,
      height: height,
      color: const Color(0xFF0B0F19),
      child: Stack(
        children: [
          Positioned.fill(child: _buildPlayerBody()),

          // Word playlist badge
          Positioned(
            top: 14,
            left: 14,
            right: 90,
            child: Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      'CLIP ${_viewModel.currentClipIndex + 1}/${_viewModel.playlist.length}'
                      '${_viewModel.currentClip != null ? ' • ${_viewModel.currentClip!.word}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _viewModel.toggleLoop,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _viewModel.isLooping
                          ? AppColors.primary.withValues(alpha: 0.8)
                          : Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.repeat_rounded,
                      size: 14,
                      color: _viewModel.isLooping
                          ? Colors.white
                          : Colors.white60,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Speed Indicator (FR-M4-06)
          Positioned(
            top: 14,
            right: 14,
            child: GestureDetector(
              onTap: _viewModel.cyclePlaybackSpeed,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  '${_viewModel.playbackSpeed}x SPEED',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),

          // Interactive Media Controls Bar (FR-M4-05, FR-M4-08..12)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.9),
                  ],
                ),
              ),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: AppColors.primaryLight,
                    ),
                    child: Slider(
                      value: _viewModel.currentProgress.clamp(0.0, 1.0),
                      onChanged: (val) => _viewModel.updateProgress(val),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_formatDuration(_viewModel.position)} / ${_formatDuration(_viewModel.clipDuration)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.skip_previous_rounded,
                              color: Colors.white70,
                              size: 24,
                            ),
                            tooltip: 'Step Back Frame',
                            onPressed: _viewModel.stepBackward,
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: _viewModel.togglePlayPause,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _viewModel.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(
                              Icons.skip_next_rounded,
                              color: Colors.white70,
                              size: 24,
                            ),
                            tooltip: 'Step Forward Frame',
                            onPressed: _viewModel.stepForward,
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.fullscreen_rounded,
                          color: Colors.white70,
                          size: 24,
                        ),
                        tooltip: 'Full Screen Mode',
                        onPressed: _toggleFullScreen,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerBody() {
    final vm = _viewModel;

    if (vm.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.videocam_off_rounded,
                size: 56,
                color: Colors.white30,
              ),
              const SizedBox(height: 12),
              Text(
                vm.errorMessage ?? 'Sign video unavailable.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: vm.retry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryLight,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (vm.isLoading || !vm.isInitialized || vm.controller == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primaryLight),
            SizedBox(height: 12),
            Text(
              'Loading sign video…',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final controller = vm.controller!;
    final aspect = controller.value.aspectRatio;
    return GestureDetector(
      onTap: vm.togglePlayPause,
      child: Center(
        child: AspectRatio(
          aspectRatio: aspect <= 0 ? 1.0 : aspect,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  Widget _buildStepItem(SignMovementStep step) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '${step.step}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  step.description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
