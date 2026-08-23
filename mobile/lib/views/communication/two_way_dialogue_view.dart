import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/entities/dialogue_message_entity.dart';
import '../../viewmodels/two_way_dialogue_viewmodel.dart';

class TwoWayDialogueView extends StatefulWidget {
  const TwoWayDialogueView({super.key});

  @override
  State<TwoWayDialogueView> createState() => _TwoWayDialogueViewState();
}

class _TwoWayDialogueViewState extends State<TwoWayDialogueView> {
  late final TwoWayDialogueViewModel _viewModel;
  final _textInputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _viewModel = TwoWayDialogueViewModel()..initSession();
  }

  @override
  void dispose() {
    _textInputController.dispose();
    _scrollController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _openSpeechSettings() {
    double speed = _viewModel.speechConfig.speed;
    double volume = _viewModel.speechConfig.volume;
    String gender = _viewModel.speechConfig.voiceGender;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Speech Synthesis Settings', style: Theme.of(context).textTheme.titleLarge),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Playback Speed Slider (FR-M3-10)
                  Text('Speech Speed: ${speed.toStringAsFixed(2)}x', style: const TextStyle(fontWeight: FontWeight.w600)),
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
                  Text('Playback Volume: ${(volume * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.w600)),
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
                  const Text('Voice Gender Accent:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
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
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openEditMessageDialog(DialogueMessage msg) {
    final controller = TextEditingController(text: msg.originalText);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Correct Dialogue Message'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Edit message text...',
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
                _viewModel.correctMessage(messageId: msg.id, correctedText: controller.text);
                Navigator.pop(ctx);
              },
              child: const Text('Apply Correction'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('2-Way Split Dialogue'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              // Auto-TTS Toggle Action
              IconButton(
                icon: Icon(
                  _viewModel.isAutoTtsEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  color: _viewModel.isAutoTtsEnabled ? AppColors.secondary : AppColors.textMuted,
                ),
                tooltip: _viewModel.isAutoTtsEnabled ? 'Auto-Speak: ON' : 'Auto-Speak: OFF',
                onPressed: () {
                  _viewModel.toggleAutoTts();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _viewModel.isAutoTtsEnabled
                            ? 'Auto-Speak Enabled: App will automatically speak incoming messages aloud!'
                            : 'Auto-Speak Disabled.',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.tune_rounded),
                tooltip: 'Speech Settings',
                onPressed: _openSpeechSettings,
              ),
              IconButton(
                icon: const Icon(Icons.save_alt_rounded),
                tooltip: 'Save Session Log',
                onPressed: () async {
                  await _viewModel.endAndSaveSession();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_viewModel.statusMessage ?? 'Session saved!'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // Language Translation Swap Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppColors.surfaceVariant,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildLanguageChip('Traveler: ${_viewModel.sourceLang.toUpperCase()}', AppColors.primary),
                    IconButton(
                      icon: const Icon(Icons.swap_horiz_rounded, color: AppColors.primary),
                      onPressed: _viewModel.swapLanguages,
                    ),
                    _buildLanguageChip('Staff: ${_viewModel.targetLang.toUpperCase()}', AppColors.accent),
                  ],
                ),
              ),

              // Split-Screen Messages Feed (FR-M3-09, FR-M3-14)
              Expanded(
                child: _viewModel.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _viewModel.messages.length,
                        itemBuilder: (context, i) {
                          final msg = _viewModel.messages[i];
                          return _buildMessageBubble(msg);
                        },
                      ),
              ),

              // Context-Aware Quick Phrases Tray (FR-M3-16)
              Container(
                height: 48,
                color: AppColors.surface,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  itemCount: _viewModel.quickPhrases.length,
                  itemBuilder: (context, i) {
                    final qp = _viewModel.quickPhrases[i];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: const Icon(Icons.flash_on, size: 14, color: AppColors.secondary),
                        label: Text(qp.getText(_viewModel.sourceLang), style: const TextStyle(fontSize: 11)),
                        onPressed: () => _viewModel.sendQuickPhrase(qp),
                      ),
                    );
                  },
                ),
              ),

              // Bottom Messaging Input Bar
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Staff Microphone Push-to-Talk
                    GestureDetector(
                      onTap: _viewModel.toggleStaffMicrophone,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _viewModel.isStaffMicActive ? AppColors.emergency : AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _viewModel.isStaffMicActive ? Icons.mic : Icons.mic_none,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Text Input Field for Traveler
                    Expanded(
                      child: TextField(
                        controller: _textInputController,
                        decoration: InputDecoration(
                          hintText: 'Type traveler message...',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          filled: true,
                          fillColor: AppColors.surfaceVariant,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (val) {
                          _viewModel.sendMessage(text: val, role: 'traveler', modality: 'typed_text');
                          _textInputController.clear();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Send Button
                    IconButton(
                      icon: const Icon(Icons.send_rounded, color: AppColors.primary),
                      onPressed: () {
                        if (_textInputController.text.trim().isNotEmpty) {
                          _viewModel.sendMessage(
                            text: _textInputController.text.trim(),
                            role: 'traveler',
                            modality: 'typed_text',
                          );
                          _textInputController.clear();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLanguageChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: color)),
    );
  }

  Widget _buildMessageBubble(DialogueMessage msg) {
    final isTraveler = msg.senderRole == 'traveler';
    return Align(
      alignment: isTraveler ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isTraveler ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(18),
        ),
        child: InkWell(
          onLongPress: () => _openEditMessageDialog(msg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    msg.senderName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isTraveler ? Colors.white70 : AppColors.textSecondary,
                    ),
                  ),
                  if (msg.isCorrected) ...[
                    const SizedBox(width: 4),
                    const Text('• edited', style: TextStyle(fontSize: 10, color: AppColors.accentLight)),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                msg.originalText,
                style: TextStyle(
                  color: isTraveler ? Colors.white : AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                msg.translatedText,
                style: TextStyle(
                  color: isTraveler ? Colors.white.withValues(alpha: 0.8) : AppColors.textSecondary,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
