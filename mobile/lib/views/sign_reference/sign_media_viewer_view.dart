import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/entities/sign_language_entity.dart';
import '../../models/entities/sign_phrase_entity.dart';
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

class _SignMediaViewerViewState extends State<SignMediaViewerView> with SingleTickerProviderStateMixin {
  late final SignMediaViewerViewModel _viewModel;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _viewModel = SignMediaViewerViewModel();
    if (widget.phrase != null) {
      _viewModel.initPhrase(phrase: widget.phrase!, initialDialect: widget.initialDialect);
    }

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _animController.addListener(() {
      if (_viewModel.isPlaying && mounted) {
        _viewModel.updateProgress(_animController.value);
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _openFeedbackDialog() {
    String issueType = 'unclear_gesture';
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.report_problem_outlined, color: AppColors.secondary),
                  SizedBox(width: 8),
                  Text('Report Sign Asset Issue'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Help us improve sign accuracy and animation clarity for travelers:'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: issueType,
                    decoration: const InputDecoration(labelText: 'Issue Type', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'unclear_gesture', child: Text('Unclear Hand / Body Movement')),
                      DropdownMenuItem(value: 'broken_video', child: Text('Broken Video / Animation Playback')),
                      DropdownMenuItem(value: 'incorrect_gloss', child: Text('Incorrect Gloss Notation')),
                      DropdownMenuItem(value: 'incorrect_translation', child: Text('Inaccurate Spoken Translation')),
                      DropdownMenuItem(value: 'other', child: Text('Other Feedback')),
                    ],
                    onChanged: (val) {
                      if (val != null) setModalState(() => issueType = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Describe what needs correction...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _viewModel.submitFeedback(
                      issueType: issueType,
                      description: descController.text.trim(),
                    );
                    if (context.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Thank you! Your feedback has been submitted for moderation.'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    }
                  },
                  child: const Text('Submit Report'),
                ),
              ],
            );
          },
        );
      },
    );
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
                children: [
                  _buildVideoSurface(height: double.infinity),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: IconButton(
                      icon: const Icon(Icons.fullscreen_exit, color: Colors.white, size: 32),
                      onPressed: _viewModel.toggleFullScreen,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final phrase = _viewModel.phrase;
        final dialect = _viewModel.currentDialect;

        return Scaffold(
          appBar: AppBar(
            title: Text('${dialect.code} Media Viewer'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.feedback_outlined),
                tooltip: 'Report Animation Issue',
                onPressed: _openFeedbackDialog,
              ),
              IconButton(
                icon: const Icon(Icons.share_rounded),
                onPressed: () {},
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Video / Animation Player Surface (FR-M4-05..12)
                _buildVideoSurface(height: 320),

                // Phrase Metadata & Multilingual Text
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.primaryLight),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(dialect.flagEmoji, style: const TextStyle(fontSize: 14)),
                                const SizedBox(width: 6),
                                Text(
                                  '${dialect.displayName} (${dialect.code})',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              phrase.categoryId.toUpperCase(),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      Text(phrase.phraseEn, style: Theme.of(context).textTheme.headlineLarge),
                      const SizedBox(height: 4),
                      Text(phrase.phraseMs, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Text(phrase.phraseZh, style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
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
                            const Icon(Icons.code_rounded, size: 18, color: AppColors.accent),
                            const SizedBox(width: 8),
                            Text(
                              'Written Gloss: ${phrase.getGloss(dialect)}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.accent),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Cross-Module Bridges: Speak Aloud (Module 3) & Copy Text
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Synthesizing speech output: "${phrase.phraseEn}"'),
                                    backgroundColor: AppColors.primary,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.volume_up_rounded, size: 18),
                              label: const Text('Play Audio (TTS)'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Phrase copied to clipboard!')),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              label: const Text('Copy Text'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Step-by-Step Hand and Body Descriptions (FR-M4-03)
                      Text('Step-by-Step Signing Guide', style: Theme.of(context).textTheme.titleLarge),
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
                                ? phrase.stepInstructions.map((step) => _buildStepItem(step)).toList()
                                : [
                                    _buildStepItem(const SignMovementStep(
                                      step: 1,
                                      title: 'Begin at Chest Level',
                                      description: 'Position both hands in front with neutral palms facing outward.',
                                    )),
                                    const Divider(height: 24),
                                    _buildStepItem(const SignMovementStep(
                                      step: 2,
                                      title: 'Complete Target Gesture',
                                      description: 'Execute the fluid sign movement matching the video playback.',
                                    )),
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
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.sign_language_rounded, size: 48, color: AppColors.primaryLight),
                ),
                const SizedBox(height: 12),
                Text(
                  '${_viewModel.perspective.toUpperCase()} VIEW • Frame ${_viewModel.currentFrame} / ${_viewModel.totalFrames}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),

          // Speed & Perspective Badges
          Positioned(
            top: 14,
            left: 14,
            child: Row(
              children: [
                GestureDetector(
                  onTap: _viewModel.togglePerspective,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.threesixty, size: 14, color: AppColors.primaryLight),
                        const SizedBox(width: 4),
                        Text(
                          '${_viewModel.perspective.toUpperCase()} VIEW',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _viewModel.toggleLoop,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: _viewModel.isLooping ? AppColors.primary.withValues(alpha: 0.8) : Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.repeat_rounded, size: 14, color: _viewModel.isLooping ? Colors.white : Colors.white60),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  '${_viewModel.playbackSpeed}x SPEED',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),

          // Interactive Media Controls Bar
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
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.9)],
                ),
              ),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: AppColors.primaryLight,
                    ),
                    child: Slider(
                      value: _viewModel.currentProgress,
                      onChanged: (val) => _viewModel.updateProgress(val),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '0:0${(_viewModel.currentProgress * 3).toInt()} / 0:03',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded, color: Colors.white70, size: 24),
                            tooltip: 'Step Back Frame',
                            onPressed: _viewModel.stepBackward,
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: _viewModel.togglePlayPause,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                              child: Icon(
                                _viewModel.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded, color: Colors.white70, size: 24),
                            tooltip: 'Step Forward Frame',
                            onPressed: _viewModel.stepForward,
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.fullscreen_rounded, color: Colors.white70, size: 24),
                        tooltip: 'Full Screen Mode',
                        onPressed: _viewModel.toggleFullScreen,
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
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 2),
                Text(step.description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
