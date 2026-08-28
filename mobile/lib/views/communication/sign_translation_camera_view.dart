import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../models/entities/sign_language_entity.dart';
import '../../services/camera_landmark_extractor_service.dart';
import '../../services/sign_frame_data.dart';
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
  final CameraLandmarkExtractorService _landmarkExtractor = CameraLandmarkExtractorService();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  CameraController? _cameraController;
  CameraDescription? _frontCamera;
  CameraDescription? _backCamera;
  CameraLensDirection _currentLensDirection = CameraLensDirection.front;

  bool _isCameraInitialized = false;
  bool _hasCameraPermission = false;
  bool _isCameraLoading = true;

  /// Accuracy-harness tray (debug builds only): long-press the tracking
  /// badge to toggle. Contains the manual letter chips (which previously
  /// faked recognition by feeding a zero tensor into the TFLite model) and
  /// the clip recorder controls.
  bool _showDebugTray = false;
  bool _isRecordingClip = false;

  // ASL / English First
  final _targetTextLanguages = const [
    {'code': 'en', 'name': 'English', 'flag': '🇺🇸'},
    {'code': 'ms', 'name': 'Bahasa Melayu', 'flag': '🇲🇾'},
    {'code': 'zh', 'name': '中文 (Mandarin)', 'flag': '🇨🇳'},
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
    _landmarkExtractor.initialize();

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
    );

    try {
      await _cameraController!.initialize();
      try {
        await _cameraController!.setZoomLevel(1.0);
      } catch (_) {}

      int frameThrottle = 0;
      bool isProcessing = false;

      // Start image stream (~6 inferences/sec, smooth 60 FPS camera UI)
      try {
        _cameraController!.startImageStream((CameraImage image) async {
          if (!_cameraViewModel.isDetecting || _currentMode != SignTranslationMode.signToText) return;

          frameThrottle++;
          if (frameThrottle % 5 != 0) return; // Process ~6 frames/sec
          if (isProcessing) return;
          isProcessing = true;

          try {
            final result = await _landmarkExtractor.processCameraFrame(image, camera);
            if (result != null && mounted) {
              _cameraViewModel.onLiveFrameRecognized(
                hasHand: result['hasHand'] == true,
                gestureText: result['character'] as String? ?? '',
                confidence: (result['confidence'] as num?)?.toDouble() ?? 0.0,
                trackingSource: result['trackingSource'] as String? ?? '',
              );
            }
          } catch (e) {
            debugPrint('Frame recognition error: $e');
          } finally {
            isProcessing = false;
          }
        });
      } catch (streamErr) {
        debugPrint('Image stream start note: $streamErr');
      }

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
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _landmarkExtractor.dispose();
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
  // ASL First & Zero Dummy Data
  // ==========================================
  Widget _buildSignToTextView() {
    final hasText = _cameraViewModel.hasContent;
    final displayText = hasText ? _cameraViewModel.currentTranslatedText : 'Awaiting sign gesture (or tap to enter)...';

    return Column(
      key: const ValueKey('sign_to_text_mode'),
      children: [
        // Top Target Dialect Selector Bar (ASL First -> BIM -> CSL)
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

        // Honest labeling: the geometric engine + TFLite model are ASL-trained;
        // BIM/CSL selection does not change recognition yet (Phase 3.3).
        if (_cameraViewModel.selectedLanguage != SignLanguageType.asl)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            color: const Color(0xFFFFF7E6),
            child: const Text(
              'ℹ️ Recognition currently uses ASL rules for all dialects — BIM/CSL coming soon',
              style: TextStyle(color: Color(0xFF92600A), fontSize: 10.5, fontWeight: FontWeight.w600),
            ),
          ),

        // Large Camera Viewport with Smooth GPU Preview
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

                  // Debug skeleton overlay: the 21 detected hand joints +
                  // face/body anchors, mapped through the same cover-fit
                  // transform as the preview (debug builds only). If the
                  // skeleton appears flipped/rotated vs your real hand,
                  // the landmark coordinate space needs fixing.
                  if (kDebugMode &&
                      _isCameraInitialized &&
                      _cameraController != null &&
                      _cameraController!.value.isInitialized)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _HandOverlayPainter(
                            hand: _cameraViewModel.handPoints,
                            anchors: _cameraViewModel.handAnchors,
                            fromMediaPipe: _cameraViewModel.handFromMediaPipe,
                            cameraWidth:
                                _cameraController!.value.previewSize?.height ?? 1,
                            cameraHeight:
                                _cameraController!.value.previewSize?.width ?? 1,
                          ),
                        ),
                      ),
                    ),

                  // Real-time Full Viewport Tracking Frame with Status Badge
                  // Long-press toggles the debug/harness tray (debug builds).
                  GestureDetector(
                    onLongPress: kDebugMode
                        ? () => setState(() => _showDebugTray = !_showDebugTray)
                        : null,
                    child: ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        width: 270,
                        height: 270,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _cameraViewModel.isHandDetected ? AppColors.success : AppColors.primaryLight.withValues(alpha: 0.5),
                            width: _cameraViewModel.isHandDetected ? 2.5 : 1.5,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          color: (_cameraViewModel.isHandDetected ? AppColors.success : AppColors.primary).withValues(alpha: 0.04),
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _cameraViewModel.isHandDetected ? AppColors.success : AppColors.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _cameraViewModel.isHandDetected
                                  ? '● TRACKING ACTIVE ($_trackingSourceLabel)'
                                  : '● SCANNING ENTIRE CAMERA VIEW...',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Debug/harness tray: manual letters + clip recorder.
                  // Hidden by default — long-press the tracking badge (debug builds only).
                  if (kDebugMode && _showDebugTray)
                    Positioned(
                      bottom: 12,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white24, width: 1),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('DEBUG HARNESS',
                                style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
                            const SizedBox(height: 6),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildGesturePoseChip('A', 'Letter A', Icons.fingerprint),
                                  _buildGesturePoseChip('B', 'Letter B', Icons.pan_tool_rounded),
                                  _buildGesturePoseChip('C', 'Letter C', Icons.circle_outlined),
                                  _buildGesturePoseChip('L', 'Letter L', Icons.straighten_rounded),
                                  _buildGesturePoseChip('V', 'Letter V', Icons.favorite_border_rounded),
                                  _buildGesturePoseChip('Y', 'Letter Y', Icons.call_made_rounded),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                _buildRecorderButton(
                                  label: _isRecordingClip ? 'Stop & Save Clip' : 'Record Clip',
                                  icon: _isRecordingClip ? Icons.stop_rounded : Icons.fiber_manual_record_rounded,
                                  color: _isRecordingClip ? AppColors.emergency : AppColors.success,
                                  onTap: _toggleClipRecording,
                                ),
                                const SizedBox(width: 6),
                                _buildRecorderButton(
                                  label: 'Copy Clips JSON',
                                  icon: Icons.copy_rounded,
                                  color: AppColors.primary,
                                  onTap: _copyClipsJson,
                                ),
                              ],
                            ),
                          ],
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
              // Header: Live Status indicator, AI confidence & Capture button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: hasText ? AppColors.success : AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        hasText
                            ? 'Recognized (${_cameraViewModel.selectedLanguage.code})'
                            : 'AI Live Tracking (${_cameraViewModel.selectedLanguage.code})',
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
                      if (hasText) ...[
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.clear_rounded, size: 18, color: AppColors.textMuted),
                          tooltip: 'Clear Recognized Text',
                          onPressed: _cameraViewModel.clearText,
                        ),
                        const SizedBox(width: 8),
                      ],
                      // Manual capture — debug harness only (the previous
                      // version faked this by feeding a zero tensor into the
                      // temporal model, which always produced a garbage class).
                      if (kDebugMode && _showDebugTray)
                        InkWell(
                          onTap: () => _cameraViewModel.debugCaptureLetter('A'),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.camera_alt_rounded, size: 13, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  'Capture Letter',
                                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 1. First Row: "Translate to :" with English First (Zero Dummy text on click)
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

  Widget _buildGesturePoseChip(String poseKey, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => _cameraViewModel.debugCaptureLetter(poseKey),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.primaryLight),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _trackingSourceLabel {
    switch (_cameraViewModel.trackingSource) {
      case 'mediapipe':
        return 'MediaPipe';
      case 'pose-synth':
        return 'Pose Fallback';
      case 'none':
        return 'No Hand';
      default:
        return '...';
    }
  }

  Future<void> _toggleClipRecording() async {
    if (_isRecordingClip) {
      final clip = _landmarkExtractor.stopClipRecording();
      setState(() => _isRecordingClip = false);
      if (mounted && clip != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Clip saved: "${clip.label}" (${clip.frames.length} frames). '
              'Tap "Copy Clips JSON" to export.'),
          duration: const Duration(seconds: 3),
        ));
      }
      return;
    }

    final labelController = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record sign clip'),
        content: TextField(
          controller: labelController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. water, hello, mom',
            labelText: 'Sign label (English gloss)',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, labelController.text.trim()),
            child: const Text('Start'),
          ),
        ],
      ),
    );

    if (label != null && label.isNotEmpty) {
      _landmarkExtractor.startClipRecording(label);
      setState(() => _isRecordingClip = true);
    }
  }

  Future<void> _copyClipsJson() async {
    final count = await _landmarkExtractor.copyRecordingsToClipboard();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(count > 0
            ? '$count clip(s) copied as JSON — paste into test/fixtures/sign_clips.json'
            : 'No clips recorded yet.'),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  Widget _buildRecorderButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // MODE 2: SPEECH / TEXT TO SIGN (Mic & Gloss)
  // ASL First
  // ==========================================
  Widget _buildSpeechToSignView() {
    final hasContent = _speechViewModel.hasContent;

    return Column(
      key: const ValueKey('speech_to_sign_mode'),
      children: [
        // Spoken Language Selector Bar (English First)
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

/// Paints the live 21-point hand skeleton and face/body anchors over the
/// camera preview. Landmarks are normalized (0..1) in the upright,
/// mirror-compensated camera space; this painter maps them through the same
/// BoxFit.cover transform the preview uses.
class _HandOverlayPainter extends CustomPainter {
  final List<SGPoint> hand;
  final SignAnchors? anchors;
  final bool fromMediaPipe;
  final double cameraWidth;
  final double cameraHeight;

  _HandOverlayPainter({
    required this.hand,
    required this.anchors,
    required this.fromMediaPipe,
    required this.cameraWidth,
    required this.cameraHeight,
  });

  static const List<List<int>> _bones = [
    [0, 1], [1, 2], [2, 3], [3, 4],       // thumb
    [0, 5], [5, 6], [6, 7], [7, 8],       // index
    [9, 10], [10, 11], [11, 12],          // middle
    [13, 14], [14, 15], [15, 16],         // ring
    [0, 17], [17, 18], [18, 19], [19, 20],// pinky
    [5, 9], [9, 13], [13, 17],            // knuckle row
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (cameraWidth < 2 || cameraHeight < 2) return;
    final scale =
        math.max(size.width / cameraWidth, size.height / cameraHeight);
    final dx = (size.width - cameraWidth * scale) / 2;
    final dy = (size.height - cameraHeight * scale) / 2;
    Offset map(SGPoint p) =>
        Offset(dx + p.x * cameraWidth * scale, dy + p.y * cameraHeight * scale);

    // Face/body anchors (orange) — verify hand/pose space alignment.
    final anchorPaint = Paint()..color = const Color(0xFFFFB300);
    void anchorDot(SGPoint? p) {
      if (p == null) return;
      canvas.drawCircle(map(p), 3.5, anchorPaint);
    }

    anchorDot(anchors?.nose);
    anchorDot(anchors?.eyeCenter);
    anchorDot(anchors?.mouthCenter);
    anchorDot(anchors?.leftEar);
    anchorDot(anchors?.rightEar);
    anchorDot(anchors?.chestCenter);

    if (hand.length < 21) return;

    final color =
        fromMediaPipe ? const Color(0xFF69F0AE) : const Color(0xFFFF6E40);
    final bonePaint = Paint()
      ..color = color.withValues(alpha: 0.95)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round;
    for (final b in _bones) {
      final a = map(hand[b[0]]);
      final c = map(hand[b[1]]);
      canvas.drawLine(a, c, shadowPaint);
      canvas.drawLine(a, c, bonePaint);
    }

    const tipIdx = {4, 8, 12, 16, 20};
    for (int i = 0; i < 21; i++) {
      final o = map(hand[i]);
      final isTip = tipIdx.contains(i);
      canvas.drawCircle(
        o,
        isTip ? 5.5 : 3.2,
        Paint()..color = isTip ? color : Colors.white,
      );
      canvas.drawCircle(
        o,
        isTip ? 5.5 : 3.2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.black87,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HandOverlayPainter oldDelegate) =>
      oldDelegate.hand != hand ||
      oldDelegate.anchors != anchors ||
      oldDelegate.fromMediaPipe != fromMediaPipe;
}
