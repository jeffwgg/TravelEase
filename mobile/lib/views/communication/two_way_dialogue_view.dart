import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/hardware_services.dart';
import '../../models/entities/dialogue_message_entity.dart';
import '../../models/repositories/feature_usage_repository.dart';
import '../../services/app_tour_controller.dart';
import '../../viewmodels/two_way_dialogue_viewmodel.dart';
import '../../widgets/app_tour_coachmark.dart';
import 'communication_history_view.dart';

/// Google Translate-style conversation view (FR-M3-08 to FR-M3-16, UC303, UC304)
/// Unified transcript: every spoken/typed sentence is auto-detected, translated
/// and separated by a divider line — no split by who said what.
class TwoWayDialogueView extends StatefulWidget {
  const TwoWayDialogueView({super.key});

  @override
  State<TwoWayDialogueView> createState() => _TwoWayDialogueViewState();
}

class _TwoWayDialogueViewState extends State<TwoWayDialogueView>
    with SingleTickerProviderStateMixin {
  late final TwoWayDialogueViewModel _viewModel;
  final _scrollController = ScrollController();
  late final AnimationController _pulseController;
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final _tourTargetKey = GlobalKey();
  bool _showInputBar = false;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _viewModel = TwoWayDialogueViewModel()..initSession();
    FeatureUsageTracker.instance.opened(TrackedFeature.twoWayDialogue);
    _pulseController = AnimationController(
      vsync: this,
      lowerBound: 0.94,
      upperBound: 1.06,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scrollController.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _langName(String code) =>
      TwoWayDialogueViewModel.supportedLanguages[code] ?? code;

  // --------------------------------------------------------------------------
  // Sheets & dialogs
  // --------------------------------------------------------------------------

  void _openLanguagePicker({required bool isSource}) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                isSource ? 'Translate from' : 'Translate to',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
            ),
            ...TwoWayDialogueViewModel.supportedLanguages.entries.map((e) {
              final selected = isSource
                  ? _viewModel.sourceLang == e.key
                  : _viewModel.targetLang == e.key;
              return ListTile(
                title: Text(
                  e.value,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
                trailing: selected
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () {
                  if (isSource) {
                    _viewModel.setSourceLang(e.key);
                  } else {
                    _viewModel.setTargetLang(e.key);
                  }
                  Navigator.pop(ctx);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Toggles the inline typing bar. This replaces the old modal bottom
  /// sheet: popping a modal route while the keyboard was dismissing it
  /// triggered the framework "_dependents.isEmpty" assertion crash.
  void _toggleKeyboardInput() {
    setState(() => _showInputBar = !_showInputBar);
    if (_showInputBar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocusNode.requestFocus();
      });
    } else {
      _inputFocusNode.unfocus();
    }
  }

  /// Sends the typed text exactly once — clearing the controller guards
  /// against double submission from both the IME action and the send button.
  void _submitTypedText() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    _viewModel.sendAutoDetectedText(text);
    FeatureUsageTracker.instance.completed(TrackedFeature.twoWayDialogue);
  }

  /// Inline input bar docked above the mic controls; stays visible while the
  /// keyboard is open because no route is pushed or popped.
  Widget _buildInlineInputBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.45),
        border: Border(
          top: BorderSide(color: AppColors.textMuted.withValues(alpha: 0.25)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _inputFocusNode,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.send,
              decoration: const InputDecoration(
                hintText: 'Type in any language — auto-detected & translated',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              onSubmitted: (_) => _submitTypedText(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send_rounded, color: AppColors.primary),
            tooltip: 'Translate & send',
            onPressed: _viewModel.isTranslating ? null : _submitTypedText,
          ),
        ],
      ),
    );
  }

  void _openSpeechSettings() {
    double speed = _viewModel.speechConfig.speed;
    double volume = _viewModel.speechConfig.volume;
    String gender = _viewModel.speechConfig.voiceGender;
    bool genderSupported = true; // Will be updated after checking TTS voices

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Check if gender is supported by trying to load voices
            Future.microtask(() async {
              final hw = HardwareServices();
              await hw.initialize(); // handles TTS init internally
              if (hw.availableVoices.isEmpty) await hw.loadVoices();
              final hasGender = hw.availableVoices.any(
                (v) => (v['gender'] ?? v['Gender'] ?? '').toString().isNotEmpty,
              );
              if (mounted) setModalState(() => genderSupported = hasGender);
            });

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Speech Synthesis Settings',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Playback Speed Slider (FR-M3-10)
                  Text(
                    'Speech Speed: ${speed.toStringAsFixed(2)}x',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Slider(
                    value: speed,
                    min: 0.5,
                    max: 2.0,
                    divisions: 6,
                    label: '${speed}x',
                    onChanged: (val) {
                      setModalState(() => speed = val);
                      _viewModel.updateSpeechConfig(speed: val);
                    },
                  ),

                  // Volume Slider (FR-M3-11)
                  Text(
                    'Playback Volume: ${(volume * 100).toInt()}%',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Slider(
                    value: volume,
                    min: 0.1,
                    max: 1.0,
                    onChanged: (val) {
                      setModalState(() => volume = val);
                      _viewModel.updateSpeechConfig(volume: val);
                    },
                  ),

                  // Voice Gender Selector (FR-M3-12)
                  const Text(
                    'Preferred Voice Gender:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  if (!genderSupported)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Voice gender selection not available on this device. '
                              'The system TTS engine does not expose gender metadata. '
                              'Download voice packages in Settings → Accessibility → Text-to-speech output.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'female', label: Text('Female')),
                        ButtonSegment(value: 'male', label: Text('Male')),
                        ButtonSegment(value: 'neutral', label: Text('Neutral')),
                      ],
                      selected: {gender},
                      onSelectionChanged: (val) {
                        setModalState(() => gender = val.first);
                        _viewModel.updateSpeechConfig(voiceGender: val.first);
                      },
                    ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.play_circle_outline_rounded),
                      label: const Text('Test Voice'),
                      onPressed: () {
                        _viewModel.speakMessage(
                          DialogueMessage(
                            id: 'preview',
                            sessionId: 'preview',
                            senderRole: 'traveler',
                            senderName: 'Preview',
                            originalText: 'This is my preferred voice.',
                            translatedText: 'Ini suara pilihan saya.',
                            sourceLanguage: _viewModel.sourceLang,
                            targetLanguage: _viewModel.targetLang,
                            inputModality: 'typed_text',
                            createdAt: DateTime.now(),
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
      },
    );
  }

  void _openEditMessageDialog(DialogueMessage msg) {
    final controller = TextEditingController(text: msg.displayText);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Correct Dialogue Text'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Fix misidentified text...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                _viewModel.correctMessage(
                  messageId: msg.id,
                  correctedText: controller.text,
                );
                Navigator.pop(ctx);
                _showSnackBar('Text corrected.');
              },
              child: const Text('Apply Correction'),
            ),
          ],
        );
      },
    );
  }

  void _openFavoritesSheet() {
    if (_viewModel.isLoadingFavorites) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Favorite Phrases',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            if (_viewModel.favoritePhrases.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.star_border_rounded,
                        size: 48,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No favorite phrases yet.\nAdd phrases from the Sign Reference screen.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: _viewModel.favoritePhrases.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final fav = _viewModel.favoritePhrases[index];
                    final phrase = fav.phrase;
                    if (phrase == null) return const SizedBox.shrink();
                    final text = phrase.getTextByLanguage(
                      _viewModel.sourceLang,
                    );
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.12,
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      title: Text(
                        text,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        phrase.categoryId.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _viewModel.sendFavoritePhrase(fav);
                        FeatureUsageTracker.instance.completed(
                          TrackedFeature.twoWayDialogue,
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        // Pulse animation only while the conversation mic is live
        if (_viewModel.isConversationMicActive) {
          if (!_pulseController.isAnimating)
            _pulseController.repeat(reverse: true);
        } else if (_pulseController.isAnimating) {
          _pulseController.stop();
          _pulseController.value = 1.0;
        }

        // Auto-scroll to the newest sentence
        if (_viewModel.messages.length != _lastMessageCount) {
          _lastMessageCount = _viewModel.messages.length;
          if (_lastMessageCount > 0) {
            FeatureUsageTracker.instance.completed(
              TrackedFeature.twoWayDialogue,
            );
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            Scaffold(
              appBar: AppBar(
                title: const Text('2-Way Dialogue'),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  // Communication History (FR-M3-17/18, UC304)
                  IconButton(
                    icon: const Icon(Icons.history_rounded),
                    tooltip: 'Communication History',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              CommunicationHistoryView(viewModel: _viewModel),
                        ),
                      );
                    },
                  ),
                  // Auto-TTS Toggle Action
                  IconButton(
                    icon: Icon(
                      _viewModel.isAutoTtsEnabled
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      color: _viewModel.isAutoTtsEnabled
                          ? AppColors.secondary
                          : AppColors.textMuted,
                    ),
                    tooltip: _viewModel.isAutoTtsEnabled
                        ? 'Auto-Speak: ON'
                        : 'Auto-Speak: OFF',
                    onPressed: () {
                      _viewModel.toggleAutoTts();
                      _showSnackBar(
                        _viewModel.isAutoTtsEnabled
                            ? 'Auto-Speak Enabled: Translations will be spoken aloud.'
                            : 'Auto-Speak Disabled.',
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.tune_rounded),
                    tooltip: 'Speech Settings',
                    onPressed: _openSpeechSettings,
                  ),
                  IconButton(
                    icon: _viewModel.isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_alt_rounded),
                    tooltip: 'Save Conversation Log to Device',
                    onPressed: _viewModel.isSaving
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final ok = await _viewModel.endAndSaveSession();
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  _viewModel.statusMessage ??
                                      (ok ? 'Saved!' : 'Nothing to save.'),
                                ),
                                backgroundColor: ok
                                    ? AppColors.success
                                    : AppColors.emergency,
                              ),
                            );
                            if (ok) _viewModel.clearStatus();
                          },
                  ),
                ],
              ),
              body: Column(
                children: [
                  // ── Language pair header, Google Translate style ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            _langName(_viewModel.sourceLang),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: AppColors.primary,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            _langName(_viewModel.targetLang),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_viewModel.isTranslating || _viewModel.isProcessingSpeech)
                    const LinearProgressIndicator(minHeight: 2),

                  // ── Unified sentence-by-sentence transcript ──
                  Expanded(
                    child: _viewModel.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.only(top: 4, bottom: 12),
                            itemCount: _viewModel.messages.length + 1,
                            itemBuilder: (context, i) {
                              if (i == _viewModel.messages.length) {
                                return _buildLiveTranscriptSlot();
                              }
                              return _buildSentenceBlock(
                                _viewModel.messages[i],
                              );
                            },
                          ),
                  ),

                  // ── Inline typing bar (shown when keyboard mode is on) ──
                  if (_showInputBar) _buildInlineInputBar(),

                  // ── Bottom controls: language pills + big mic ──
                  KeyedSubtree(
                    key: _tourTargetKey,
                    child: _buildBottomControls(),
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: AppTourCoachmark(
                feature: AppTourFeature.twoWayDialogue,
                targetKey: _tourTargetKey,
                title: 'Two-Way Dialogue',
                message: 'Speak or type for a live conversation.',
              ),
            ),
          ],
        );
      },
    );
  }

  // --------------------------------------------------------------------------
  // Transcript pieces
  // --------------------------------------------------------------------------

  /// One translated sentence: detected-language tag, original caption, and its
  /// translation, closed by a divider line marking the end of that speaker's
  /// sentence (FR-M3-09, FR-M3-14, FR-M3-15).
  Widget _buildSentenceBlock(DialogueMessage msg) {
    final isSourceSide = msg.sourceLanguage == _viewModel.sourceLang;
    final tagColor = isSourceSide ? AppColors.primary : AppColors.accent;

    return Column(
      children: [
        InkWell(
          onLongPress: () => _openEditMessageDialog(msg),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Detected language tag — hints which party spoke this sentence
                Row(
                  children: [
                    Icon(
                      msg.inputModality == 'speech_to_text'
                          ? Icons.mic_rounded
                          : msg.inputModality == 'quick_phrase'
                          ? Icons.flash_on_rounded
                          : msg.inputModality == 'sign_to_text'
                          ? Icons.sign_language_rounded
                          : Icons.keyboard_rounded,
                      size: 12,
                      color: tagColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _langName(msg.sourceLanguage),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: tagColor,
                      ),
                    ),
                    if (msg.isCorrected) ...[
                      const SizedBox(width: 6),
                      const Text(
                        '• corrected',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.accentLight,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                // Original caption text (FR-M3-15 correction applies here)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        msg.displayText,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.volume_up_rounded,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                      tooltip: 'Speak Aloud',
                      onPressed: () => _viewModel.speakMessage(msg),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // Translated caption (FR-M3-14)
                Text(
                  msg.translatedText,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Sentence divider — each line marks a new sentence / speaker turn
        const Divider(indent: 20, endIndent: 20, height: 1),
      ],
    );
  }

  /// Live interim transcript while the mic keeps listening, or an empty hint.
  Widget _buildLiveTranscriptSlot() {
    if (!_viewModel.isConversationMicActive) {
      if (_viewModel.messages.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                size: 40,
                color: AppColors.textMuted.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              const Text(
                'Tap the mic and start talking.\nEach sentence is auto-detected and translated —\nin both directions, hands-free.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.emergency,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _viewModel.isProcessingSpeech
                    ? 'Translating (${_langName(_viewModel.processingTurnLang ?? _viewModel.activeListenLang)})...'
                    : 'Listening (${_langName(_viewModel.activeListenLang)})...',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          if (_viewModel.liveTranscript.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _viewModel.liveTranscript,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                height: 1.3,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Bottom controls (Google Translate conversation style)
  // --------------------------------------------------------------------------

  Widget _buildBottomControls() {
    final micActive = _viewModel.isConversationMicActive;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Selected languages row
          Row(
            children: [
              Expanded(
                child: _buildLanguagePill(
                  code: _viewModel.sourceLang,
                  color: AppColors.primary,
                  onTap: () => _openLanguagePicker(isSource: true),
                ),
              ),
              const SizedBox(width: 10),
              // Swap button
              Material(
                color: AppColors.surfaceVariant,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _viewModel.swapLanguages,
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.swap_horiz_rounded,
                      size: 22,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildLanguagePill(
                  code: _viewModel.targetLang,
                  color: AppColors.accent,
                  onTap: () => _openLanguagePicker(isSource: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Turn control: automatic handover after each window (default) or
          // manual flipping via the turn button next to the mic.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _viewModel.isAutoTurnEnabled
                    ? 'Auto turn-switch'
                    : 'Manual turn — use the flip button',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              SizedBox(
                height: 28,
                child: Switch(
                  value: _viewModel.isAutoTurnEnabled,
                  activeThumbColor: AppColors.primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (_) => _viewModel.toggleAutoTurn(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Big voice button with keyboard (left), mic (centered), favorites+flip (right)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left section: Keyboard button (fixed width — mirrors the
              // right slot so the mic button stays centered)
              SizedBox(
                width: 96,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _buildSmallActionButton(
                    icon: _showInputBar
                        ? Icons.keyboard_hide_rounded
                        : Icons.keyboard_rounded,
                    tooltip: _showInputBar
                        ? 'Hide typing bar'
                        : 'Type a message to translate',
                    onPressed: _toggleKeyboardInput,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Center: Mic button
              GestureDetector(
                onTap: () async {
                  await _viewModel.toggleConversationMic();
                  if (_viewModel.statusMessage != null && mounted) {
                    _showSnackBar(
                      _viewModel.statusMessage!,
                      color: AppColors.emergency,
                    );
                    _viewModel.clearStatus();
                  }
                },
                child: ScaleTransition(
                  scale: _pulseController,
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: micActive
                          ? AppColors.primaryDark
                          : AppColors.primary,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(
                            alpha: micActive ? 0.4 : 0.25,
                          ),
                          blurRadius: micActive ? 20 : 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.mic_rounded,
                      size: 34,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Right section: Favorites + Flip turn. Both slots are 96px:
              // star (40) + gap (8) + flip-or-placeholder (44) needs 92.
              SizedBox(
                width: 96,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildSmallActionButton(
                        icon: Icons.star_rounded,
                        tooltip: 'Favorite phrases for quick insertion',
                        onPressed: _openFavoritesSheet,
                      ),
                      const SizedBox(width: 8),
                      if (!_viewModel.isAutoTurnEnabled)
                        _buildSmallActionButton(
                          icon: Icons.autorenew_rounded,
                          tooltip: 'Flip turn — hand mic to the other language',
                          onPressed: () => _viewModel.flipTurn(),
                        )
                      else
                        const SizedBox(width: 44),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            micActive
                ? 'Listening continuously — tap to stop'
                : 'Tap the mic to start the conversation',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguagePill({
    required String code,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _langName(code),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              Icon(Icons.arrow_drop_down_rounded, size: 20, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surfaceVariant,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 22, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}
