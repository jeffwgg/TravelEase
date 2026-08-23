import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../models/entities/sign_language_entity.dart';
import '../../viewmodels/sign_translation_camera_viewmodel.dart';
import '../../viewmodels/speech_to_sign_viewmodel.dart';

enum SignTranslationMode {
  signToText, // Sign Language (Camera) -> Text & Voice
  speechToSign, // Speech / Text (Mic) -> Sign Animation & Gloss
}

class SignTranslationCameraView extends StatefulWidget {
  final SignTranslationMode initialMode;
  const SignTranslationCameraView({
    super.key,
    this.initialMode = SignTranslationMode.signToText,
  });

  @override
  State<SignTranslationCameraView> createState() => _SignTranslationCameraViewState();
}

class _SignTranslationCameraViewState extends State<SignTranslationCameraView> with SingleTickerProviderStateMixin {
  late SignTranslationMode _currentMode;
  late final SignTranslationCameraViewModel _cameraViewModel;
  late final SpeechToSignViewModel _speechViewModel;
  final TextEditingController _speechInputController = TextEditingController();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  CameraController? _cameraController;
  CameraDescription? _frontCamera;
  CameraDescription? _backCamera;
  CameraLensDirection _currentLensDirection = CameraLensDirection.front;

  bool _isCameraInitialized = false;
  bool _hasCameraPermission = false;
  bool _isCameraLoading = true;

  final _targetTextLanguages = const [
    {'code': 'ms', 'name': 'Bahasa Melayu', 'flag': '🇲🇾'},
    {'code': 'zh', 'name': '中文 (Mandarin)', 'flag': '🇨🇳'},
    {'code': 'en', 'name': 'English', 'flag': '🇺🇸'},
  ];

  final _spokenLanguages = const [
    {'code': 'en', 'name': 'English', 'flag': '🇺🇸'},
    {'code': 'ms', 'name': 'Bahasa Melayu', 'flag': '🇲🇾'},
    {'code': 'zh', 'name': '中文 (Mandarin)', 'flag': '🇨🇳'},
  ];

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialMode;
    _cameraViewModel = SignTranslationCameraViewModel();
    _speechViewModel = SpeechToSignViewModel();
    _speechInputController.text = _speechViewModel.currentInputText;

    // Real-time Text Area Synchronization: as words are spoken, update the text box immediately
    _speechViewModel.addListener(() {
      if (_speechInputController.text != _speechViewModel.currentInputText) {
        _speechInputController.text = _speechViewModel.currentInputText;
        _speechInputController.selection = TextSelection.collapsed(
          offset: _speechInputController.text.length,
        );
      }
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Initialize real camera
    _initializeRealCamera();
  }

  Future<void> _initializeRealCamera() async {
    setState(() => _isCameraLoading = true);
    try {
      final status = await Permission.camera.request();
      if (status.isGranted) {
        _hasCameraPermission = true;
        final allCameras = await availableCameras();
        if (allCameras.isNotEmpty) {
          try {
            _frontCamera = allCameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front);
          } catch (_) {
            _frontCamera = null;
          }

          try {
            _backCamera = allCameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back);
          } catch (_) {
            _backCamera = null;
          }

          final initialCamera = _frontCamera ?? _backCamera ?? allCameras.first;
          _currentLensDirection = initialCamera.lensDirection;
          await _startCameraInstance(initialCamera);
        } else {
          if (mounted) setState(() => _isCameraLoading = false);
        }
      } else {
        if (mounted) {
          setState(() {
            _hasCameraPermission = false;
            _isCameraLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Camera initialization: $e');
      if (mounted) setState(() => _isCameraLoading = false);
    }
  }

  Future<void> _startCameraInstance(CameraDescription camera) async {
    await _cameraController?.dispose();
    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _cameraController!.initialize();
      try {
        await _cameraController!.setZoomLevel(1.0);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _currentLensDirection = camera.lensDirection;
          _isCameraInitialized = true;
          _isCameraLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Camera controller start error: $e');
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
          _isCameraLoading = false;
        });
      }
    }
  }

  void _flipCamera() async {
    if (_frontCamera != null && _backCamera != null) {
      if (_currentLensDirection == CameraLensDirection.front) {
        await _startCameraInstance(_backCamera!);
      } else {
        await _startCameraInstance(_frontCamera!);
      }
    }
  }

  bool get _canFlipCamera => _frontCamera != null && _backCamera != null;

  void _toggleTranslationMode() {
    setState(() {
      _currentMode = _currentMode == SignTranslationMode.signToText
          ? SignTranslationMode.speechToSign
          : SignTranslationMode.signToText;
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _pulseController.dispose();
    _speechInputController.dispose();
    _cameraViewModel.dispose();
    _speechViewModel.dispose();
    super.dispose();
  }

  /// Directly edit the active translated text on tap
  void _editActiveTranslatedText() {
    final controller = TextEditingController(text: _cameraViewModel.currentTranslatedText);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Direct Text Edit',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textMuted),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Type below to enter or modify the phrase:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Type phrase here...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (controller.text.trim().isNotEmpty) {
                      _cameraViewModel.updateActiveTranslatedText(controller.text.trim());
                    }
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: const Text('Update Phrase'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_cameraViewModel, _speechViewModel]),
      builder: (context, _) {
        final isSignToText = _currentMode == SignTranslationMode.signToText;

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0.5,
            iconTheme: const IconThemeData(color: AppColors.textPrimary),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  context.go('/home');
                }
              },
            ),
            // Swapping 2-way position switcher: [ Sign ⇄ Speech ] <-> [ Speech ⇄ Sign ]
            title: InkWell(
              onTap: _toggleTranslationMode,
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSignToText ? Icons.sign_language_rounded : Icons.mic_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isSignToText ? 'Sign' : 'Speech',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.swap_horiz_rounded,
                        color: AppColors.primary,
                        size: 15,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSignToText ? Icons.mic_rounded : Icons.sign_language_rounded,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isSignToText ? 'Speech' : 'Sign',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (isSignToText) ...[
                // Auto-Speak Toggle Icon
                IconButton(
                  icon: Icon(
                    _cameraViewModel.isAutoSpeakEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                    color: _cameraViewModel.isAutoSpeakEnabled ? AppColors.primary : AppColors.textMuted,
                    size: 24,
                  ),
                  tooltip: _cameraViewModel.isAutoSpeakEnabled ? 'Auto-Speak: ON' : 'Tap to Enable Auto-Speak',
                  onPressed: () {
                    if (!_cameraViewModel.isAutoSpeakEnabled) {
                      _cameraViewModel.speakAloud();
                    }
                    _cameraViewModel.toggleAutoSpeak();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _cameraViewModel.isAutoSpeakEnabled
                              ? 'Auto-Speak Enabled: Automatically speaks translated signs aloud!'
                              : 'Auto-Speak Disabled.',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                // Flip Camera Button
                if (_canFlipCamera)
                  IconButton(
                    icon: const Icon(Icons.flip_camera_ios_rounded, color: AppColors.textPrimary, size: 22),
                    tooltip: _currentLensDirection == CameraLensDirection.front ? 'Switch to Back Camera' : 'Switch to Front Camera',
                    onPressed: _flipCamera,
                  ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<SignLanguageType>(
                      value: _speechViewModel.selectedSignLang,
                      icon: const Icon(Icons.arrow_drop_down, color: AppColors.primary),
                      items: SignLanguageType.values.map((lang) {
                        return DropdownMenuItem(
                          value: lang,
                          child: Text('${lang.flagEmoji} ${lang.code}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) _speechViewModel.switchSignDialect(v);
                      },
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
            ],
          ),
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: isSignToText ? _buildSignToTextView() : _buildSpeechToSignView(),
          ),
        );
      },
    );
  }

  // ==========================================
  // MODE 1: SIGN TO TEXT & VOICE (Camera AI)
  // Clean State with No Dummy Text
  // ==========================================
  Widget _buildSignToTextView() {
    final hasText = _cameraViewModel.hasContent;
    final displayText = hasText ? _cameraViewModel.currentTranslatedText : 'Awaiting sign gesture (or tap to enter)...';

    return Column(
      key: const ValueKey('sign_to_text_mode'),
      children: [
        // Top Target Dialect Selector Bar (BIM / ASL / CSL)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppColors.cardBorder, width: 1)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text(
                  'Input Dialect: ',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                ...SignLanguageType.values.map((lang) {
                  final isSelected = _cameraViewModel.selectedLanguage == lang;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Text(lang.flagEmoji, style: const TextStyle(fontSize: 14)),
                      label: Text('${lang.code} (${lang.countryCode})'),
                      selected: isSelected,
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppColors.textPrimary,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                        fontSize: 12,
                      ),
                      backgroundColor: AppColors.surfaceVariant,
                      side: BorderSide(color: isSelected ? AppColors.primary : AppColors.cardBorder),
                      onSelected: (val) {
                        if (val) _cameraViewModel.switchDialect(lang);
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        ),

        // Large Camera Viewport
        Expanded(
          flex: 7,
          child: Container(
            width: double.infinity,
            color: Colors.black,
            child: ClipRect(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_isCameraInitialized && _cameraController != null && _cameraController!.value.isInitialized)
                    Positioned.fill(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _cameraController!.value.previewSize?.height ?? MediaQuery.of(context).size.width,
                          height: _cameraController!.value.previewSize?.width ?? MediaQuery.of(context).size.height,
                          child: CameraPreview(_cameraController!),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      color: const Color(0xFF0F172A),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isCameraLoading)
                              const CircularProgressIndicator(color: AppColors.primary)
                            else ...[
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.primaryLight, width: 2),
                                ),
                                child: const Icon(Icons.sign_language_rounded, size: 48, color: AppColors.primaryLight),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _hasCameraPermission ? 'AI Live Gesture Tracking' : 'Camera Access Needed',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Position hands in frame for ${_cameraViewModel.selectedLanguage.name}',
                                style: const TextStyle(color: Colors.white60, fontSize: 11),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                  // Gesture Tracking Frame Overlay
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 230,
                      height: 230,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.primaryLight, width: 2),
                        borderRadius: BorderRadius.circular(24),
                        color: AppColors.primary.withValues(alpha: 0.05),
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _currentLensDirection == CameraLensDirection.front
                                ? '● FRONT CAMERA (30 FPS)'
                                : '● BACK CAMERA (30 FPS)',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Streamlined Bottom Section with 1 Unified Text Area
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            border: const Border(top: BorderSide(color: AppColors.cardBorder, width: 1.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Status indicator, AI confidence & Test button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: hasText ? AppColors.success : AppColors.textMuted,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        hasText ? 'Recognized (${_cameraViewModel.selectedLanguage.code})' : 'Camera Ready (${_cameraViewModel.selectedLanguage.code})',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (hasText)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.successLight.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.success, width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.verified, size: 13, color: AppColors.success),
                              const SizedBox(width: 4),
                              Text(
                                '${(_cameraViewModel.confidenceScore * 100).toInt()}% Conf.',
                                style: const TextStyle(color: AppColors.success, fontSize: 10.5, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => _cameraViewModel.simulateGestureRecognition(),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_mode_rounded, size: 12, color: AppColors.primary),
                              SizedBox(width: 3),
                              Text('Demo Gesture', style: TextStyle(color: AppColors.primary, fontSize: 10.5, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 1. First Row: "Translate to :" with the 3 language buttons
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Text(
                      'Translate to: ',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 4),
                    ..._targetTextLanguages.map((lang) {
                      final isSelected = _cameraViewModel.targetOutputLang == lang['code'];
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          avatar: Text(lang['flag']!, style: const TextStyle(fontSize: 13)),
                          label: Text(lang['name']!),
                          selected: isSelected,
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : AppColors.textPrimary,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 11.5,
                          ),
                          backgroundColor: AppColors.surfaceVariant,
                          side: BorderSide(color: isSelected ? AppColors.primary : AppColors.cardBorder),
                          onSelected: (val) {
                            if (val) _cameraViewModel.switchTargetOutputLang(lang['code']!);
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 2. Second Row: [ 1 Single Editable Area where translated text is located ] + [ Audio Speak Button ]
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Unified Single Editable Text Area (Clean state without dummy text)
                  Expanded(
                    child: InkWell(
                      onTap: _editActiveTranslatedText,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: hasText ? AppColors.primary.withValues(alpha: 0.35) : AppColors.cardBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayText,
                                style: TextStyle(
                                  color: hasText ? AppColors.textPrimary : AppColors.textMuted,
                                  fontSize: hasText ? 16 : 13.5,
                                  fontWeight: hasText ? FontWeight.w800 : FontWeight.w500,
                                  fontStyle: hasText ? FontStyle.normal : FontStyle.italic,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.edit, size: 15, color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Dedicated Audio Speak Button beside the editable area
                  ElevatedButton.icon(
                    onPressed: hasText ? _cameraViewModel.speakAloud : null,
                    icon: const Icon(Icons.volume_up_rounded, size: 17, color: Colors.white),
                    label: const Text('Speak', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // MODE 2: SPEECH / TEXT TO SIGN (Mic & Gloss)
  // Real-Time Spoken Input Sync
  // ==========================================
  Widget _buildSpeechToSignView() {
    final hasContent = _speechViewModel.hasContent;

    return Column(
      key: const ValueKey('speech_to_sign_mode'),
      children: [
        // Spoken Language Selector Bar (White Theme)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppColors.cardBorder, width: 1)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text('Voice Language: ', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                ..._spokenLanguages.map((l) {
                  final isSelected = _speechViewModel.spokenLang == l['code'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('${l['flag']} ${l['name']}'),
                      selected: isSelected,
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppColors.textPrimary,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 11,
                      ),
                      backgroundColor: AppColors.surfaceVariant,
                      side: BorderSide(color: isSelected ? AppColors.primary : AppColors.cardBorder),
                      onSelected: (val) {
                        if (val) {
                          _speechViewModel.switchSpokenLanguage(l['code']!);
                        }
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        ),

        // Animated Sign Display Surface (Clean White Viewport)
        Expanded(
          flex: 4,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primaryLight, width: 2),
                        ),
                        child: const Icon(Icons.sign_language, size: 40, color: AppColors.primary),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${_speechViewModel.selectedSignLang.name} Signing Animation',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasContent
                            ? (_speechViewModel.isFingerspelling ? 'Fingerspelling Mode (UC302 Alt A3)' : 'Standard Gesture Vocabulary')
                            : 'Ready: Speak or tap a quick phrase below',
                        style: TextStyle(
                          color: _speechViewModel.isFingerspelling ? AppColors.secondary : AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                // Gloss Token Chips Carousel (Only displayed when real speech/text exists)
                if (hasContent && _speechViewModel.signTokens.isNotEmpty)
                  Positioned(
                    bottom: 10,
                    left: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.cardBorder),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Gloss: ${_speechViewModel.translatedSignGloss}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800, fontSize: 11.5),
                                ),
                              ),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: Icon(
                                  _speechViewModel.isPlayingAnimation ? Icons.pause_circle : Icons.play_circle,
                                  color: AppColors.primary,
                                  size: 20,
                                ),
                                onPressed: _speechViewModel.toggleAnimation,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _speechViewModel.signTokens.asMap().entries.map((entry) {
                                final idx = entry.key;
                                final token = entry.value;
                                final isCurrent = idx == _speechViewModel.currentTokenIndex;
                                return GestureDetector(
                                  onTap: () => _speechViewModel.selectToken(idx),
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isCurrent ? AppColors.primary : AppColors.surfaceVariant,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: isCurrent ? AppColors.primary : AppColors.cardBorder),
                                    ),
                                    child: Text(
                                      token,
                                      style: TextStyle(
                                        color: isCurrent ? Colors.white : AppColors.textPrimary,
                                        fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Predefined Quick Phrases Section
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.bolt_rounded, size: 14, color: AppColors.primary),
                  SizedBox(width: 4),
                  Text(
                    'Predefined Quick Phrases:',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _speechViewModel.quickPhrases.map((phraseItem) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(
                          phraseItem['label'] as String,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                        backgroundColor: AppColors.surfaceVariant,
                        side: const BorderSide(color: AppColors.cardBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        onPressed: () {
                          _speechViewModel.selectQuickPhrase(phraseItem);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),

        // Speech Input and Text Entry Controls with Real-Time Typing & Speech Updates
        Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Real-Time Synchronized Text Entry Field
              TextField(
                controller: _speechInputController,
                maxLines: 2,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Type text or tap microphone to speak...',
                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send_rounded, color: AppColors.primary, size: 20),
                    onPressed: () => _speechViewModel.translateInput(_speechInputController.text),
                  ),
                ),
                onChanged: (val) => _speechViewModel.translateInput(val),
                onSubmitted: (val) => _speechViewModel.translateInput(val),
              ),
              const SizedBox(height: 8),

              // Microphone Record Button in selected Voice Language
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _speechViewModel.toggleMicrophone,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _speechViewModel.isListening ? AppColors.emergency : AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_speechViewModel.isListening ? AppColors.emergency : AppColors.primary).withValues(alpha: 0.3),
                            blurRadius: 14,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        _speechViewModel.isListening ? Icons.mic : Icons.mic_none,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                _speechViewModel.isListening
                    ? 'Listening in ${_speechViewModel.spokenLang == "ms" ? "Bahasa Melayu" : _speechViewModel.spokenLang == "zh" ? "中文 (Mandarin)" : "English"}...'
                    : 'Tap mic to speak in ${_speechViewModel.spokenLang == "ms" ? "Bahasa Melayu" : _speechViewModel.spokenLang == "zh" ? "中文" : "English"}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
