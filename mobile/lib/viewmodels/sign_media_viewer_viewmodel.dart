import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../core/hardware_services.dart';
import '../models/entities/sign_language_entity.dart';
import '../models/entities/sign_phrase_entity.dart';
import '../models/repositories/sign_reference_repository.dart';
import '../models/sign_word_video_library.dart';

/// ViewModel for Sign Media Video playback (FR-M4-01, FR-M4-05 to FR-M4-12, UC402).
///
/// Plays a phrase as a sequential playlist of per-word videos resolved from
/// [SignWordVideoLibrary] based on the active sign language gloss.
class SignMediaViewerViewModel extends ChangeNotifier {
  final SignReferenceRepository _repository;

  SignMediaViewerViewModel({SignReferenceRepository? repository})
      : _repository = repository ?? SignReferenceRepository();

  SignPhrase? _phrase;
  SignLanguageType _currentDialect = SignLanguageType.bim;

  List<SignWordClip> _playlist = const [];
  int _currentClipIndex = 0;
  VideoPlayerController? _controller;
  bool _isLoading = false;
  bool _isAdvancing = false;
  bool _clipEndHandled = false;
  String? _errorMessage;

  // Clip initialized in the background so playlist transitions are instant.
  VideoPlayerController? _preloadedController;
  int _preloadedIndex = -1;

  bool _isLooping = true;
  double _playbackSpeed = 1.0;
  bool _isFullScreen = false;
  bool _isSpeaking = false;
  String? _speakingLang;
  bool _isFavorite = false;

  // Getters
  SignPhrase? get phrase => _phrase;
  SignLanguageType get currentDialect => _currentDialect;
  List<SignWordClip> get playlist => _playlist;
  int get currentClipIndex => _currentClipIndex;
  SignWordClip? get currentClip => _currentClipIndex < _playlist.length ? _playlist[_currentClipIndex] : null;
  VideoPlayerController? get controller => _controller;
  bool get isLoading => _isLoading;
  bool get hasError => _errorMessage != null;
  String? get errorMessage => _errorMessage;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isPlaying => _controller?.value.isPlaying ?? false;
  bool get isBuffering => _controller?.value.isBuffering ?? false;
  bool get isLooping => _isLooping;
  double get playbackSpeed => _playbackSpeed;
  bool get isFullScreen => _isFullScreen;
  bool get isSpeaking => _isSpeaking;
  String? get speakingLang => _speakingLang;

  /// Whether the current phrase is starred by the signed-in account.
  bool get isFavorite => _isFavorite;

  Duration get position => _controller?.value.position ?? Duration.zero;
  Duration get clipDuration => _controller?.value.duration ?? Duration.zero;

  double get currentProgress {
    final totalMs = clipDuration.inMilliseconds;
    if (totalMs <= 0) return 0;
    return (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
  }

  int get currentFrame => position.inMilliseconds * SignWordVideoLibrary.fps ~/ 1000;
  int get totalFrames => clipDuration.inMilliseconds * SignWordVideoLibrary.fps ~/ 1000;

  Future<void> initPhrase({required SignPhrase phrase, SignLanguageType? initialDialect}) async {
    _phrase = phrase;
    _isFavorite = false;
    if (initialDialect != null) {
      _currentDialect = initialDialect;
    }
    notifyListeners();
    unawaited(_refreshFavorite());
    await _rebuildPlaylist();
  }

  /// FR-M4-01: toggle between BIM and ASL visual assets.
  Future<void> switchDialect(SignLanguageType dialect) async {
    if (dialect == _currentDialect) return;
    _currentDialect = dialect;
    notifyListeners();
    await _rebuildPlaylist();
  }

  Future<void> retry() => _rebuildPlaylist();

  Future<void> _rebuildPlaylist() async {
    _disposePreloaded();
    _disposeController();
    _playlist = const [];
    _currentClipIndex = 0;
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();

    final gloss = _phrase?.getGloss(_currentDialect) ?? '';
    final words = SignWordVideoLibrary.parseGlossWords(gloss);
    final clips = await SignWordVideoLibrary.resolveClipSources(
      words: words,
      language: _currentDialect,
    );

    if (clips.isEmpty) {
      _isLoading = false;
      _errorMessage = 'No $_currentDialect sign video found for this phrase. '
          'Add assets/signs/${_currentDialect.code.toLowerCase()}/<word>.mp4 or report a missing asset.';
      notifyListeners();
      return;
    }
    _playlist = clips;
    await _loadClip(0, autoPlay: true);
  }

  /// Copy a bundled asset to a real file (OEM devices sometimes fail to
  /// decode straight from the asset stream).
  Future<File?> _copyAssetToFile(SignWordClip clip) async {
    try {
      final data = await rootBundle.load(clip.source);
      final dir = await getTemporaryDirectory();
      final safeName = clip.source.replaceAll(RegExp('[^a-zA-Z0-9._-]'), '_');
      final file = File('${dir.path}/sign_$safeName');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return file;
    } catch (e) {
      debugPrint('[SignVideo] Asset->File copy failed: $e');
      return null;
    }
  }

  Future<void> _loadClip(int index, {bool autoPlay = false, bool viaFile = false}) async {
    if (index < 0 || index >= _playlist.length) return;

    // Instant switch when this clip was preloaded while the previous played.
    if (!viaFile &&
        identical(_preloadedIndex, index) &&
        _preloadedController?.value.isInitialized == true) {
      final promoted = _preloadedController!;
      final old = _controller;
      _preloadedController = null;
      _preloadedIndex = -1;
      old?.removeListener(_onControllerUpdated);
      old?.dispose();
      _controller = promoted;
      _currentClipIndex = index;
      _clipEndHandled = false;
      _isLoading = false;
      _errorMessage = null;
      promoted.setPlaybackSpeed(_playbackSpeed);
      promoted.addListener(_onControllerUpdated);
      debugPrint('[SignVideo] Switched to preloaded clip $index instantly');
      if (autoPlay) promoted.play();
      notifyListeners();
      _queuePreloadAfter(index);
      return;
    }

    _disposePreloaded();
    _disposeController();
    _currentClipIndex = index;
    _clipEndHandled = false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final clip = _playlist[index];
    VideoPlayerController? newController;
    try {
      if (clip.isNetwork) {
        newController = VideoPlayerController.networkUrl(Uri.parse(clip.source));
      } else if (viaFile) {
        final file = await _copyAssetToFile(clip);
        if (file == null) throw Exception('Could not copy asset to temp file');
        newController = VideoPlayerController.file(file);
      } else {
        newController = VideoPlayerController.asset(clip.source);
      }

      _controller = newController;
      newController.setPlaybackSpeed(_playbackSpeed);
      newController.addListener(_onControllerUpdated);
      debugPrint('[SignVideo] Initializing clip $index '
          '(${viaFile ? 'file' : clip.isNetwork ? 'network' : 'asset'}): ${clip.source}');

      // Fail fast instead of spinning forever on corrupt/unsupported files
      await newController.initialize().timeout(const Duration(seconds: 10));
      if (newController.value.duration <= Duration.zero) {
        throw Exception('Video has no duration');
      }
      debugPrint('[SignVideo] Ready: ${clip.source} '
          '(${newController.value.duration.inMilliseconds}ms, ${newController.value.size})');
    } catch (e) {
      debugPrint('[SignVideo] FAILED (${viaFile ? 'file' : 'asset'}): ${clip.source} -> $e');
      final wasCurrent = identical(_controller, newController);
      if (wasCurrent) {
        _disposeController();
      } else if (newController != null) {
        await newController.dispose();
      }

      // Retry once from a real file before giving up (Huawei/OEM asset quirk)
      if (!clip.isNetwork && !viaFile) {
        await _loadClip(index, autoPlay: autoPlay, viaFile: true);
        return;
      }

      if (wasCurrent) {
        _isLoading = false;
        _errorMessage =
            'Could not play "${clip.word}" (${clip.source}). '
            'Check the file is a valid landscape H.264 .mp4, then retry.';
        notifyListeners();
      }
      return;
    }

    if (!identical(_controller, newController)) {
      await newController.dispose();
      return;
    }
    _isLoading = false;
    if (autoPlay) newController.play();
    notifyListeners();
    _queuePreloadAfter(index);
  }

  void _disposeController() {
    final old = _controller;
    _controller = null;
    if (old != null) {
      old.removeListener(_onControllerUpdated);
      old.dispose();
    }
  }

  void _disposePreloaded() {
    final p = _preloadedController;
    _preloadedController = null;
    _preloadedIndex = -1;
    p?.dispose();
  }

  /// Queue background initialization of the clip that plays next so word
  /// transitions in the playlist are seamless (no loading gap).
  void _queuePreloadAfter(int index) {
    final int next;
    if (index + 1 < _playlist.length) {
      next = index + 1;
    } else if (_isLooping && _playlist.isNotEmpty) {
      next = 0; // loop wraps back to the first clip
    } else {
      return;
    }
    unawaited(_preloadClip(next));
  }

  Future<void> _preloadClip(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    if (_preloadedController != null && identical(_preloadedIndex, index)) return;
    _disposePreloaded();

    final clip = _playlist[index];
    final VideoPlayerController c;
    if (clip.isNetwork) {
      c = VideoPlayerController.networkUrl(Uri.parse(clip.source));
    } else {
      c = VideoPlayerController.asset(clip.source);
    }
    _preloadedController = c;
    _preloadedIndex = index;
    try {
      await c.initialize().timeout(const Duration(seconds: 10));
      if (!identical(_preloadedController, c)) {
        await c.dispose();
        return;
      }
      if (c.value.duration <= Duration.zero) throw Exception('Video has no duration');
      c.setPlaybackSpeed(_playbackSpeed);
      debugPrint('[SignVideo] Preloaded clip $index: ${clip.source}');
    } catch (e) {
      debugPrint('[SignVideo] Preload failed for clip $index (${clip.source}): $e');
      if (identical(_preloadedController, c)) {
        _preloadedController = null;
        _preloadedIndex = -1;
      }
      try {
        await c.dispose();
      } catch (_) {}
    }
  }

  void _onControllerUpdated() {
    if (_isAdvancing) return;
    final value = _controller?.value;
    if (value == null || !value.isInitialized) {
      notifyListeners();
      return;
    }
    final totalMs = value.duration.inMilliseconds;
    if (!_clipEndHandled && totalMs > 0 && value.position.inMilliseconds >= totalMs) {
      _handleClipEnd();
      return;
    }
    notifyListeners();
  }

  Future<void> _handleClipEnd() async {
    if (_isAdvancing) return;
    _isAdvancing = true;
    _clipEndHandled = true;
    try {
      final nextIndex = _currentClipIndex + 1;
      if (nextIndex < _playlist.length) {
        await _loadClip(nextIndex, autoPlay: true);
      } else if (_isLooping) {
        await _loadClip(0, autoPlay: true);
      } else {
        final c = _controller;
        if (c != null) {
          await c.pause();
          await c.seekTo(Duration.zero);
        }
      }
    } finally {
      _isAdvancing = false;
      notifyListeners();
    }
  }

  // FR-M4-05: play / pause on demand
  void togglePlayPause() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    notifyListeners();
  }

  // FR-M4-08: pause on a specific frame / scrub
  Future<void> updateProgress(double progress) async {
    final c = _controller;
    final totalMs = clipDuration.inMilliseconds;
    if (c == null || totalMs <= 0) return;
    final ms = (progress.clamp(0.0, 1.0) * totalMs).round();
    await c.seekTo(Duration(milliseconds: ms));
    notifyListeners();
  }

  // FR-M4-09/10: step frame by frame (1 frame = 1000ms / fps)
  Future<void> stepForward() => _stepByFrame(1);

  // FR-M4-11: step backward frame by frame
  Future<void> stepBackward() => _stepByFrame(-1);

  Future<void> _stepByFrame(int direction) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _isAdvancing) return;
    if (c.value.isPlaying) c.pause();

    final frameMs = 1000 ~/ SignWordVideoLibrary.fps;
    final targetMs = c.value.position.inMilliseconds + direction * frameMs;
    final totalMs = c.value.duration.inMilliseconds;

    if (targetMs >= totalMs && totalMs > 0) {
      if (_currentClipIndex < _playlist.length - 1) {
        _clipEndHandled = true;
        _isAdvancing = true;
        try {
          await _loadClip(_currentClipIndex + 1);
        } finally {
          _isAdvancing = false;
          notifyListeners();
        }
        return;
      }
      if (_isLooping) {
        _clipEndHandled = true;
        _isAdvancing = true;
        try {
          await _loadClip(0);
        } finally {
          _isAdvancing = false;
          notifyListeners();
        }
        return;
      }
      await updateProgress(1.0);
      return;
    }

    if (targetMs < 0) {
      if (_currentClipIndex > 0) {
        _clipEndHandled = true;
        _isAdvancing = true;
        try {
          await _loadClip(_currentClipIndex - 1);
          await updateProgress(1.0);
        } finally {
          _isAdvancing = false;
          notifyListeners();
        }
        return;
      }
      await updateProgress(0.0);
      return;
    }

    await c.seekTo(Duration(milliseconds: targetMs));
    notifyListeners();
  }

  // FR-M4-06: adjust playback speed
  void cyclePlaybackSpeed() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final currentIndex = speeds.indexOf(_playbackSpeed);
    _playbackSpeed = speeds[(currentIndex + 1) % speeds.length];
    _controller?.setPlaybackSpeed(_playbackSpeed);
    notifyListeners();
  }

  // FR-M4-07: loop continuously
  Future<void> toggleLoop() async {
    _isLooping = !_isLooping;
    final atEnd = clipDuration > Duration.zero && position >= clipDuration;
    if (_isLooping && atEnd && isInitialized && !(isPlaying)) {
      _clipEndHandled = true;
      _isAdvancing = true;
      try {
        await _loadClip(0, autoPlay: true);
      } finally {
        _isAdvancing = false;
        notifyListeners();
      }
      return;
    }
    notifyListeners();
  }

  // FR-M4-12: full-screen display mode (orientation handled in the view)
  void toggleFullScreen() {
    _isFullScreen = !_isFullScreen;
    notifyListeners();
  }

  /// Cross-module bridge: speak text aloud via device TTS (Module 3).
  Future<void> speakAloud({required String text, required String language}) async {
    if (text.isEmpty || _isSpeaking) return;
    _isSpeaking = true;
    _speakingLang = language;
    notifyListeners();
    try {
      await HardwareServices().speak(text: text, language: language);
    } finally {
      _isSpeaking = false;
      _speakingLang = null;
      notifyListeners();
    }
  }

  /// Re-check the account's favorites so the star reflects reality when the
  /// page opens (the repository mirrors the last successful server read, so
  /// this also works offline after a prior load).
  Future<void> _refreshFavorite() async {
    final p = _phrase;
    if (p == null) return;
    try {
      final favorites =
          await _repository.getFavoritePhrases(_repository.currentUserId);
      _isFavorite = favorites.any((f) => f.phraseId == p.id);
      notifyListeners();
    } catch (_) {
      // Star stays off; a failed favorites load must not break playback.
    }
  }

  /// Toggle the current phrase's star for the signed-in account — the same
  /// data the Favorites page and the dictionary star read/write.
  Future<bool> toggleFavorite() async {
    final p = _phrase;
    if (p == null) return false;
    final userId = _repository.currentUserId;
    _isFavorite = !_isFavorite;
    notifyListeners();
    if (_isFavorite) {
      await _repository.addFavoritePhrase(userId, p.id);
    } else {
      await _repository.removeFavoritePhrase(userId, p.id);
    }
    return _isFavorite;
  }

  @override
  void dispose() {
    _disposePreloaded();
    _disposeController();
    super.dispose();
  }
}
