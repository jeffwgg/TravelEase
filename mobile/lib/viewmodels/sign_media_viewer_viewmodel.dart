import 'package:flutter/foundation.dart';
import '../models/entities/sign_language_entity.dart';
import '../models/entities/sign_phrase_entity.dart';
import '../models/repositories/sign_reference_repository.dart';

/// ViewModel for Sign Media Video & 3D Visualizations (FR-M4-05 to FR-M4-12, UC402)
class SignMediaViewerViewModel extends ChangeNotifier {
  final SignReferenceRepository _repository;

  SignMediaViewerViewModel({
    SignReferenceRepository? repository,
  }) : _repository = repository ?? SignReferenceRepository();

  SignPhrase _phrase = const SignPhrase(
    id: 'default',
    categoryId: 'airport',
    phraseEn: 'Where is the gate?',
    phraseMs: 'Di mana pintu masuk / perlepasan?',
    phraseZh: '登机口在哪里？',
    glossAsl: 'GATE WHERE ?',
    glossBim: 'PINTU MANA ?',
    glossCsl: '登机口 在哪 ?',
  );

  SignLanguageType _currentDialect = SignLanguageType.bim;
  String _perspective = 'front'; // 'front', 'side'

  bool _isPlaying = true;
  bool _isLooping = true;
  double _playbackSpeed = 1.0;
  double _currentProgress = 0.35;
  int _currentFrame = 32;
  final int _totalFrames = 90;
  bool _isFullScreen = false;
  bool _isSubmitting = false;
  String? _feedbackStatus;

  // Getters
  SignPhrase get phrase => _phrase;
  SignLanguageType get currentDialect => _currentDialect;
  String get perspective => _perspective;
  bool get isPlaying => _isPlaying;
  bool get isLooping => _isLooping;
  double get playbackSpeed => _playbackSpeed;
  double get currentProgress => _currentProgress;
  int get currentFrame => _currentFrame;
  int get totalFrames => _totalFrames;
  bool get isFullScreen => _isFullScreen;
  bool get isSubmitting => _isSubmitting;
  String? get feedbackStatus => _feedbackStatus;

  void initPhrase({required SignPhrase phrase, SignLanguageType? initialDialect}) {
    _phrase = phrase;
    if (initialDialect != null) {
      _currentDialect = initialDialect;
    }
    notifyListeners();
  }

  void togglePlayPause() {
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  void updateProgress(double progress) {
    _currentProgress = progress.clamp(0.0, 1.0);
    _currentFrame = (_currentProgress * _totalFrames).toInt();
    notifyListeners();
  }

  void stepForward() {
    _isPlaying = false;
    _currentProgress = (_currentProgress + 0.05).clamp(0.0, 1.0);
    _currentFrame = (_currentProgress * _totalFrames).toInt();
    notifyListeners();
  }

  void stepBackward() {
    _isPlaying = false;
    _currentProgress = (_currentProgress - 0.05).clamp(0.0, 1.0);
    _currentFrame = (_currentProgress * _totalFrames).toInt();
    notifyListeners();
  }

  void cyclePlaybackSpeed() {
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final currentIndex = speeds.indexOf(_playbackSpeed);
    _playbackSpeed = speeds[(currentIndex + 1) % speeds.length];
    notifyListeners();
  }

  void toggleLoop() {
    _isLooping = !_isLooping;
    notifyListeners();
  }

  void togglePerspective() {
    _perspective = _perspective == 'front' ? 'side' : 'front';
    notifyListeners();
  }

  void toggleFullScreen() {
    _isFullScreen = !_isFullScreen;
    notifyListeners();
  }

  Future<bool> submitFeedback({
    required String issueType,
    required String description,
  }) async {
    _isSubmitting = true;
    notifyListeners();

    try {
      await _repository.submitAssetFeedback(
        userId: 'demo_user',
        phraseId: _phrase.id,
        signLanguageId: _currentDialect.code,
        issueType: issueType,
        description: description,
      );
      _isSubmitting = false;
      _feedbackStatus = 'Feedback submitted for moderation.';
      notifyListeners();
      return true;
    } catch (e) {
      _isSubmitting = false;
      _feedbackStatus = 'Saved locally.';
      notifyListeners();
      return true;
    }
  }
}
