import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kProfileMode;
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../models/entities/sign_language_entity.dart';
import '../../models/repositories/feature_usage_repository.dart';
import '../../services/camera_landmark_extractor_service.dart';
import '../../services/sign_frame_data.dart';
import '../../services/app_tour_controller.dart';
import '../../viewmodels/sign_translation_camera_viewmodel.dart';
import '../../widgets/app_tour_coachmark.dart';

/// Debug overlays (skeleton painter, harness tray) are hidden in release
/// builds but shown in BOTH debug and profile — profiling runs are exactly
/// where the landmark overlay is most useful.
const bool _debugOverlayEnabled = kDebugMode || kProfileMode;

class SignTranslationCameraView extends StatefulWidget {
  const SignTranslationCameraView({super.key});
  @override
  State<SignTranslationCameraView> createState() =>
      _SignTranslationCameraViewState();
}

class _SignTranslationCameraViewState extends State<SignTranslationCameraView>
    with SingleTickerProviderStateMixin {
  late final SignTranslationCameraViewModel _cameraViewModel;
  final CameraLandmarkExtractorService _landmarkExtractor =
      CameraLandmarkExtractorService();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  CameraController? _cameraController;
  bool _isSwitchingCamera = false;
  CameraDescription? _frontCamera;
  CameraDescription? _backCamera;
  CameraLensDirection _currentLensDirection = CameraLensDirection.front;

  bool _isCameraInitialized = false;
  bool _hasCameraPermission = false;
  bool _isCameraLoading = true;
  final _signTourTargetKey = GlobalKey();

  /// Clip-harness tray (debug builds only): long-press the tracking badge
  /// to toggle. Contains the record-clip, batch-capture and clip-export
  /// controls.
  bool _showDebugTray = false;
  bool _isRecordingClip = false;
  bool _hasRecordedSignTranslation = false;

  // Batch capture: type one word, sign it N times with pauses; the motion
  // gate segments each repetition into its own labeled clip automatically.
  String? _batchLabel;
  int _batchTarget = 0;
  int _batchDone = 0;
  bool get _batchActive => _batchLabel != null;

  // ASL / English First
  final _targetTextLanguages = const [
    {'code': 'en', 'name': 'English', 'flag': '🇺🇸'},
    {'code': 'ms', 'name': 'Bahasa Melayu', 'flag': '🇲🇾'},
    {'code': 'zh', 'name': '中文 (Mandarin)', 'flag': '🇨🇳'},
  ];

  @override
  void initState() {
    super.initState();
    _cameraViewModel = SignTranslationCameraViewModel();
    _cameraViewModel.addListener(_trackSignTranslationCompletion);
    FeatureUsageTracker.instance.opened(TrackedFeature.signTranslate);
    _landmarkExtractor.initialize();

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
            _frontCamera = allCameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.front,
            );
          } catch (_) {
            _frontCamera = null;
          }

          try {
            _backCamera = allCameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.back,
            );
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
    if (_isSwitchingCamera) return;
    _isSwitchingCamera = true;
    try {
      // Detach the old controller from the UI and wait out the current frame
      // before disposing it — disposing while CameraPreview still holds it
      // throws "buildPreview() was called on a disposed CameraController"
      // when the dispose notification triggers a rebuild.
      final oldController = _cameraController;
      if (mounted) {
        setState(() {
          _cameraController = null;
          _isCameraInitialized = false;
          _isCameraLoading = true;
        });
        await WidgetsBinding.instance.endOfFrame;
      }
      try {
        await oldController?.stopImageStream();
      } catch (_) {}
      await oldController?.dispose();

      await _startNewCameraInstance(camera);
    } finally {
      _isSwitchingCamera = false;
    }
  }

  Future<void> _startNewCameraInstance(CameraDescription camera) async {
    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      // hand_landmarker 3.x and the NV21 conversion both need 3-plane YUV.
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _cameraController!.initialize();
      try {
        await _cameraController!.setZoomLevel(1.0);
      } catch (_) {}

      bool isProcessing = false;

      // Start image stream (every frame; the extractor's hand loop is
      // sub-millisecond and pose runs on its own decoupled cadence)
      try {
        _cameraController!.startImageStream((CameraImage image) async {
          if (!_cameraViewModel.isDetecting) return;
          if (isProcessing) {
            _landmarkExtractor.noteFrameDropped();
            return;
          }
          isProcessing = true;

          try {
            final result = await _landmarkExtractor.processCameraFrame(
              image,
              camera,
            );
            if (result != null && mounted) {
              _cameraViewModel.onLiveFrameRecognized(
                hasHand: result['hasHand'] == true,
                gestureText: result['character'] as String? ?? '',
                confidence: (result['confidence'] as num?)?.toDouble() ?? 0.0,
                trackingSource: result['trackingSource'] as String? ?? '',
                handPoints: result['hand'] as List<SGPoint>?,
                anchors: result['anchors'] as SignAnchors?,
                handFromMediaPipe: result['hasMediaPipeHand'] == true,
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

  /// Guidance tracking: the first recognized text of a visit records a
  /// "completed" event (the Supabase RPC keeps only the first timestamp; the
  /// flag just stops the per-frame rebuild from re-firing the write).
  void _trackSignTranslationCompletion() {
    if (_hasRecordedSignTranslation || !_cameraViewModel.hasContent) return;
    _hasRecordedSignTranslation = true;
    FeatureUsageTracker.instance.completed(TrackedFeature.signTranslate);
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _landmarkExtractor.dispose();
    _pulseController.dispose();
    _cameraViewModel.removeListener(_trackSignTranslationCompletion);
    _cameraViewModel.dispose();
    super.dispose();
  }

  /// Directly edit the active translated text on tap
  void _editActiveTranslatedText() {
    final controller = TextEditingController(
      text: _cameraViewModel.currentTranslatedText,
    );
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
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
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
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Type phrase here...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
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
                      _cameraViewModel.updateActiveTranslatedText(
                        controller.text.trim(),
                      );
                    }
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: const Text('Update Phrase'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
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
      listenable: _cameraViewModel,
      builder: (context, _) {
        // Single source of truth for model routing: the extractor's mode
        // follows the viewmodel's dialect on EVERY rebuild, so no dialect
        // change path (now or later) can leave it on the wrong model.
        _landmarkExtractor.bimMode =
            _cameraViewModel.selectedLanguage == SignLanguageType.bim;
        return Stack(
          fit: StackFit.expand,
          children: [
            Scaffold(
              backgroundColor: Colors.white,
              appBar: AppBar(
                backgroundColor: Colors.white,
                elevation: 0.5,
                iconTheme: const IconThemeData(color: AppColors.textPrimary),
                leading: IconButton(
                  icon: const Icon(
                    Icons.arrow_back,
                    color: AppColors.textPrimary,
                  ),
                  onPressed: () {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    } else {
                      context.go('/home');
                    }
                  },
                ),
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.sign_language_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Sign to Text',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                actions: [
                  // Auto-Speak Toggle Icon
                  IconButton(
                    icon: Icon(
                      _cameraViewModel.isAutoSpeakEnabled
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      color: _cameraViewModel.isAutoSpeakEnabled
                          ? AppColors.primary
                          : AppColors.textMuted,
                      size: 24,
                    ),
                    tooltip: _cameraViewModel.isAutoSpeakEnabled
                        ? 'Auto-Speak: ON'
                        : 'Tap to Enable Auto-Speak',
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
                      icon: const Icon(
                        Icons.flip_camera_ios_rounded,
                        color: AppColors.textPrimary,
                        size: 22,
                      ),
                      tooltip:
                          _currentLensDirection == CameraLensDirection.front
                          ? 'Switch to Back Camera'
                          : 'Switch to Front Camera',
                      onPressed: _flipCamera,
                    ),
                  const SizedBox(width: 4),
                ],
              ),
              body: _buildSignToTextView(),
            ),
            Positioned.fill(
              child: AppTourCoachmark(
                feature: AppTourFeature.signTranslate,
                targetKey: _signTourTargetKey,
                title: 'Live sign translation',
                message: 'Allow camera access, keep your hands in this frame, and sign naturally to translate your gesture.',
              ),
            ),
          ],
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
    final displayText = hasText
        ? _cameraViewModel.currentTranslatedText
        : 'Complete sentence appears here as you sign…';

    return Column(
      key: const ValueKey('sign_to_text_mode'),
      children: [
        // Top Target Dialect Selector Bar (ASL First -> BIM -> CSL)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: AppColors.cardBorder, width: 1),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text(
                  'Input Dialect: ',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                ...SignLanguageType.values
                    // CSL input is not offered on this screen yet.
                    .where((lang) => lang != SignLanguageType.csl)
                    .map((lang) {
                      final isSelected =
                          _cameraViewModel.selectedLanguage == lang;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Text(
                            lang.flagEmoji,
                            style: const TextStyle(fontSize: 14),
                          ),
                          label: Text('${lang.code} (${lang.countryCode})'),
                          selected: isSelected,
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : AppColors.textPrimary,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w500,
                            fontSize: 12,
                          ),
                          backgroundColor: AppColors.surfaceVariant,
                          side: BorderSide(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.cardBorder,
                          ),
                          onSelected: (val) {
                            if (!val) return;
                            // Recognition routing follows automatically: the
                            // builder syncs _landmarkExtractor.bimMode from the
                            // viewmodel's dialect on the rebuild this triggers.
                            _cameraViewModel.switchDialect(lang);
                          },
                        ),
                      );
                    }),
              ],
            ),
          ),
        ),

        // Large Camera Viewport with Smooth GPU Preview
        Expanded(
          flex: 7,
          child: Container(
            key: _signTourTargetKey,
            width: double.infinity,
            color: Colors.black,
            child: ClipRect(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_isCameraInitialized &&
                      _cameraController != null &&
                      _cameraController!.value.isInitialized)
                    Positioned.fill(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width:
                              _cameraController!.value.previewSize?.height ??
                              MediaQuery.of(context).size.width,
                          height:
                              _cameraController!.value.previewSize?.width ??
                              MediaQuery.of(context).size.height,
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
                              const CircularProgressIndicator(
                                color: AppColors.primary,
                              )
                            else ...[
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.15,
                                  ),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.primaryLight,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.sign_language_rounded,
                                  size: 48,
                                  color: AppColors.primaryLight,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _hasCameraPermission
                                    ? 'AI Live Gesture Tracking'
                                    : 'Camera Access Needed',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Position hands in frame for ${_cameraViewModel.selectedLanguage.name}',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                  // Batch capture progress — the tray can be closed while
                  // signing, so the counter lives on the preview itself.
                  if (_batchActive)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.fiber_manual_record_rounded,
                              size: 12,
                              color: AppColors.emergency,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$_batchLabel  $_batchDone/$_batchTarget',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Debug skeleton overlay: the 21 detected hand joints +
                  // face/body anchors, mapped through the same cover-fit
                  // transform as the preview (debug/profile builds only). If
                  // the skeleton appears flipped/rotated vs your real hand,
                  // the landmark coordinate space needs fixing.
                  if (_debugOverlayEnabled &&
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
                                _cameraController!.value.previewSize?.height ??
                                1,
                            cameraHeight:
                                _cameraController!.value.previewSize?.width ??
                                1,
                            // Model coords are third-person (unmirrored);
                            // the front-camera preview is the mirrored
                            // selfie view — flip for display only.
                            mirrorX:
                                _currentLensDirection ==
                                CameraLensDirection.front,
                          ),
                        ),
                      ),
                    ),

                  // Real-time Full Viewport Tracking Frame with Status Badge
                  // Long-press toggles the debug/harness tray (debug builds).
                  GestureDetector(
                    onLongPress: _debugOverlayEnabled
                        ? () => setState(() => _showDebugTray = !_showDebugTray)
                        : null,
                    child: ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        width: 270,
                        height: 270,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _cameraViewModel.isHandDetected
                                ? AppColors.success
                                : AppColors.primaryLight.withValues(alpha: 0.5),
                            width: _cameraViewModel.isHandDetected ? 2.5 : 1.5,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          color:
                              (_cameraViewModel.isHandDetected
                                      ? AppColors.success
                                      : AppColors.primary)
                                  .withValues(alpha: 0.04),
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _cameraViewModel.isHandDetected
                                  ? AppColors.success
                                  : AppColors.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _cameraViewModel.isHandDetected
                                  ? '● TRACKING ACTIVE ($_trackingSourceLabel)'
                                  : '● SCANNING ENTIRE CAMERA VIEW...',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Harness tray: clip recorder controls.
                  // Hidden by default — long-press the tracking badge (debug builds only).
                  if (_debugOverlayEnabled && _showDebugTray)
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
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildRecorderButton(
                                    label: _isRecordingClip
                                        ? 'Stop & Save Clip'
                                        : 'Record Clip',
                                    icon: _isRecordingClip
                                        ? Icons.stop_rounded
                                        : Icons.fiber_manual_record_rounded,
                                    color: _isRecordingClip
                                        ? AppColors.emergency
                                        : AppColors.success,
                                    onTap: _toggleClipRecording,
                                  ),
                                  const SizedBox(width: 6),
                                  // Batch: one word, 12 auto-segmented clips.
                                  _buildRecorderButton(
                                    label: _batchActive
                                        ? 'Stop Batch ($_batchDone/$_batchTarget)'
                                        : 'Batch ×12',
                                    icon: _batchActive
                                        ? Icons.stop_rounded
                                        : Icons.burst_mode_rounded,
                                    color: _batchActive
                                        ? AppColors.emergency
                                        : AppColors.secondary,
                                    onTap: _toggleBatchRecording,
                                  ),
                                  const SizedBox(width: 6),
                                  // Clipboard drops large exports on Android —
                                  // save the session to a file and open the
                                  // system share sheet instead.
                                  _buildRecorderButton(
                                    label: 'Save & Share Clips',
                                    icon: Icons.ios_share_rounded,
                                    color: AppColors.accent,
                                    onTap: _shareClipsJson,
                                  ),
                                ],
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
        ),

        // Streamlined Bottom Section with 1 Unified Text Area
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            border: const Border(
              top: BorderSide(color: AppColors.cardBorder, width: 1.5),
            ),
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
                          color: hasText
                              ? AppColors.success
                              : AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        hasText
                            ? 'Recognized (${_cameraViewModel.selectedLanguage.code})'
                            : 'AI Live Tracking (${_cameraViewModel.selectedLanguage.code})',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Space is reserved whether or not a word is recognized,
                      // so the panel below never jumps when recognition lands.
                      Visibility(
                        visible: hasText,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.successLight.withValues(
                                  alpha: 0.25,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppColors.success,
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.verified,
                                    size: 13,
                                    color: AppColors.success,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${(_cameraViewModel.confidenceScore * 100).toInt()}% Conf.',
                                    style: const TextStyle(
                                      color: AppColors.success,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: const Icon(
                                Icons.clear_rounded,
                                size: 18,
                                color: AppColors.textMuted,
                              ),
                              tooltip: 'Clear Recognized Text',
                              onPressed: _cameraViewModel.clearText,
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // WORDS BOX: every accepted recognition stacks here (both
              // dialects); the sentence box below assembles them into a
              // complete travel phrase that the TTS speaks.
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.translate_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Text(
                          _cameraViewModel.recognizedWords.isEmpty
                              ? 'Sign words — they stack here'
                              : _cameraViewModel.wordsText,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _cameraViewModel.recognizedWords.isEmpty
                                ? AppColors.textMuted
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    if (_cameraViewModel.recognizedWords.isNotEmpty) ...[
                      Text(
                        _cameraViewModel.phraseMatched ? '→ sentence ✓' : '…',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 1. First Row: "Translate to :" with English First (Zero Dummy text on click)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Text(
                      'Translate to: ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    ..._targetTextLanguages.map((lang) {
                      final isSelected =
                          _cameraViewModel.targetOutputLang == lang['code'];
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          avatar: Text(
                            lang['flag']!,
                            style: const TextStyle(fontSize: 13),
                          ),
                          label: Text(lang['name']!),
                          selected: isSelected,
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : AppColors.textPrimary,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            fontSize: 11.5,
                          ),
                          backgroundColor: AppColors.surfaceVariant,
                          side: BorderSide(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.cardBorder,
                          ),
                          onSelected: (val) {
                            if (val) {
                              _cameraViewModel.switchTargetOutputLang(
                                lang['code']!,
                              );
                            }
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: hasText
                                ? AppColors.primary.withValues(alpha: 0.35)
                                : AppColors.cardBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayText,
                                style: TextStyle(
                                  color: hasText
                                      ? AppColors.textPrimary
                                      : AppColors.textMuted,
                                  fontSize: hasText ? 16 : 13.5,
                                  fontWeight: hasText
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  fontStyle: hasText
                                      ? FontStyle.normal
                                      : FontStyle.italic,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.edit,
                                size: 15,
                                color: AppColors.primary,
                              ),
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
                    icon: const Icon(
                      Icons.volume_up_rounded,
                      size: 17,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Speak',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: AppColors.primary.withValues(
                        alpha: 0.4,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Clip saved: "${clip.label}" (${clip.frames.length} frames). '
              'Tap "Save & Share Clips" to export.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
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

  // ── Batch capture: one word, N auto-segmented gesture clips ───────────
  Future<void> _toggleBatchRecording() async {
    if (_batchActive) {
      _endBatch('stopped');
      return;
    }
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batch capture one word'),
        content: SizedBox(
          width: 260,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'BIM gloss e.g. saya · ASL word e.g. doctor',
              labelText: 'Word (12 clips)',
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Start ×12'),
          ),
        ],
      ),
    );
    if (label == null || label.isEmpty || !mounted) return;
    setState(() {
      _batchLabel = label.toLowerCase();
      _batchDone = 0;
      _batchTarget = 12;
    });
    _landmarkExtractor.onGestureWindowClosed = _onBatchWindow;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Sign the word 12 times — pause ~1s between reps, '
          'each sign is captured automatically.',
        ),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _onBatchWindow(List<SignFrameData> frames) {
    final label = _batchLabel;
    if (label == null || !mounted) return;
    _landmarkExtractor.clipRecorder.captureClip(label, frames);
    final total = _landmarkExtractor.clipRecorder.countFor(label);
    setState(() => _batchDone = total);
    if (total >= _batchTarget) {
      _endBatch('complete');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 900),
          content: Text('$total/$_batchTarget'),
        ),
      );
    }
  }

  void _endBatch(String why) {
    final label = _batchLabel;
    _landmarkExtractor.onGestureWindowClosed = null;
    if (mounted) {
      setState(() {
        _batchLabel = null;
        _batchTarget = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Batch $why: $_batchDone clip(s) of "$label"'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Large JSON exports exceed the Android clipboard (silently dropped,
  /// worst on Huawei), so this writes the session to a file and opens the
  /// system share sheet — save to Files, send via email/Drive, or pull it
  /// over adb using the path shown in the snackbar.
  Future<void> _shareClipsJson() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await _landmarkExtractor.exportRecordingsToFile();
      await SharePlus.instance.share(
        ShareParams(
          subject: 'BIM landmark clips',
          files: [XFile(path, mimeType: 'application/json')],
        ),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text('Saved:\n$path', style: const TextStyle(fontSize: 11)),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Clip export failed: $e'),
          duration: const Duration(seconds: 4),
        ),
      );
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
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
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
    required this.mirrorX,
  });

  /// Display-only horizontal flip: model coords are third-person
  /// (unmirrored); the front-camera preview is the mirrored selfie view.
  final bool mirrorX;

  static const List<List<int>> _bones = [
    [0, 1], [1, 2], [2, 3], [3, 4], // thumb
    [0, 5], [5, 6], [6, 7], [7, 8], // index
    [9, 10], [10, 11], [11, 12], // middle
    [13, 14], [14, 15], [15, 16], // ring
    [0, 17], [17, 18], [18, 19], [19, 20], // pinky
    [5, 9], [9, 13], [13, 17], // knuckle row
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (cameraWidth < 2 || cameraHeight < 2) return;
    final scale = math.max(
      size.width / cameraWidth,
      size.height / cameraHeight,
    );
    final dx = (size.width - cameraWidth * scale) / 2;
    final dy = (size.height - cameraHeight * scale) / 2;
    Offset map(SGPoint p) => Offset(
      dx + (mirrorX ? 1 - p.x : p.x) * cameraWidth * scale,
      dy + p.y * cameraHeight * scale,
    );

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

    final color = fromMediaPipe
        ? const Color(0xFF69F0AE)
        : const Color(0xFFFF6E40);
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
