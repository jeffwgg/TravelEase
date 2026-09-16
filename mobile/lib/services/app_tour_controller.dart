import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/repositories/home_guidance_repository.dart';

/// Coordinates the one complete, first-login tour.
///
/// The tour deliberately has one completion state rather than a state per
/// feature: a traveller can skip an explanation and still continue through
/// the rest of the first-login tour. Help Center can also launch any one
/// guide without marking the complete tour as finished.
enum AppTourFeature {
  signTranslate,
  speechToSign,
  twoWayDialogue,
  signDictionary,
  requestHelp,
  sos,
  complete,
  queueTracking,
}

enum HomeGuideSection {
  quickActions,
  location,
  spokenAnnouncements,
  officialAnnouncements,
  queueTracking,
}

/// The three replayable journeys available from Help Center.
enum AppTourGuide { full, homeAnnouncements, communication, assistanceSafety }

class AppTourController extends ChangeNotifier {
  AppTourController._();

  static final AppTourController instance = AppTourController._();

  final HomeGuidanceRepository _repository = HomeGuidanceRepository();

  bool _isRunning = false;
  AppTourGuide _guide = AppTourGuide.full;
  bool _shouldSaveCompletion = false;
  AppTourFeature? _currentFeature;
  HomeGuideSection? _homeSection;
  int _sosStep = 0;

  bool get isRunning => _isRunning;
  bool get isShowingHomeGuide => _isRunning && _currentFeature == null;
  HomeGuideSection? get homeSection => _homeSection;
  bool get isHomeAnnouncementsGuide => _guide == AppTourGuide.homeAnnouncements;
  int get sosStep => _sosStep;

  bool isShowing(AppTourFeature feature) =>
      _isRunning && _currentFeature == feature;

  /// Starts the complete first-login tour at Home. [force] supports an
  /// explicit complete-tour entry point without changing its completion record.
  Future<bool> start({bool force = false}) async {
    if (force) {
      _isRunning = true;
      _guide = AppTourGuide.full;
      _shouldSaveCompletion = true;
      _currentFeature = null;
      _homeSection = null;
      _sosStep = 0;
      notifyListeners();
      return true;
    }
    if (_isRunning) return isShowingHomeGuide;
    if (!await _repository.shouldShowHomeTour()) return false;

    _isRunning = true;
    _guide = AppTourGuide.full;
    _shouldSaveCompletion = true;
    _currentFeature = null;
    _homeSection = null;
    _sosStep = 0;
    notifyListeners();
    return true;
  }

  /// Starts the Home and announcements journey from Help Center.
  void startHomeAnnouncementsGuide(BuildContext context) {
    _isRunning = true;
    _guide = AppTourGuide.homeAnnouncements;
    _shouldSaveCompletion = false;
    _currentFeature = null;
    _homeSection = null;
    _sosStep = 0;
    notifyListeners();
    context.go('/home');
  }

  /// Starts the communication journey from Help Center.
  void startCommunicationGuide(BuildContext context) {
    _isRunning = true;
    _guide = AppTourGuide.communication;
    _shouldSaveCompletion = false;
    _currentFeature = AppTourFeature.signTranslate;
    _homeSection = null;
    _sosStep = 0;
    notifyListeners();
    context.go(_routeFor(_currentFeature!));
  }

  /// Starts the SOS, help request, and queue journey from Help Center.
  void startAssistanceSafetyGuide(BuildContext context) {
    _isRunning = true;
    _guide = AppTourGuide.assistanceSafety;
    _shouldSaveCompletion = false;
    _currentFeature = AppTourFeature.sos;
    _homeSection = null;
    _sosStep = 0;
    notifyListeners();
    context.go('/home');
  }

  /// Called after the Home explanations have been shown.
  void leaveHome(BuildContext context) {
    if (!_isRunning) return;
    if (_guide == AppTourGuide.homeAnnouncements) {
      _currentFeature = AppTourFeature.complete;
      notifyListeners();
      context.go(_routeFor(AppTourFeature.complete));
      return;
    }
    _currentFeature = AppTourFeature.sos;
    notifyListeners();
  }

  /// Moves the complete first-login tour to its next feature.
  void advance(BuildContext context) {
    final current = _currentFeature;
    if (!_isRunning || current == null) return;

    final next = switch (_guide) {
      AppTourGuide.full => switch (current) {
        AppTourFeature.sos => AppTourFeature.signTranslate,
        AppTourFeature.signTranslate => AppTourFeature.speechToSign,
        AppTourFeature.speechToSign => AppTourFeature.twoWayDialogue,
        AppTourFeature.twoWayDialogue => AppTourFeature.signDictionary,
        AppTourFeature.signDictionary => AppTourFeature.requestHelp,
        AppTourFeature.requestHelp => AppTourFeature.complete,
        AppTourFeature.complete => null,
        // Queue Tracking is introduced from Home, after announcements.
        AppTourFeature.queueTracking => null,
      },
      AppTourGuide.communication => switch (current) {
        AppTourFeature.signTranslate => AppTourFeature.speechToSign,
        AppTourFeature.speechToSign => AppTourFeature.twoWayDialogue,
        AppTourFeature.twoWayDialogue => AppTourFeature.signDictionary,
        AppTourFeature.signDictionary => AppTourFeature.complete,
        AppTourFeature.complete => null,
        _ => null,
      },
      AppTourGuide.assistanceSafety => switch (current) {
        AppTourFeature.sos => AppTourFeature.requestHelp,
        AppTourFeature.requestHelp => AppTourFeature.complete,
        AppTourFeature.complete => null,
        _ => null,
      },
      AppTourGuide.homeAnnouncements => null,
    };

    if (next == null) {
      _complete();
      return;
    }

    _currentFeature = next;
    notifyListeners();
    context.go(_routeFor(next));
  }

  /// SOS needs two short coach marks: how to activate it, then what happens.
  void advanceSos(BuildContext context) {
    if (!isShowing(AppTourFeature.sos)) return;
    if (_sosStep == 0) {
      _sosStep = 1;
      notifyListeners();
      return;
    }
    _sosStep = 0;
    advance(context);
  }

  /// Completes the first-login tour from its final confirmation screen.
  void finishTour(BuildContext context) {
    _complete();
    context.go('/home');
  }

  /// Confirms whether the traveller wants to leave the complete tour. A
  /// single guide opened from Help Center is only dismissed and does not
  /// change the first-login tour's completion state.
  Future<bool> confirmAndSkip(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Skip tour?'),
        content: const Text('You can start a guide again from Help Center.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep touring'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Skip tour'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return false;

    final returnToHome = _currentFeature != null;
    _complete();
    if (returnToHome && context.mounted) context.go('/home');
    return true;
  }

  String _routeFor(AppTourFeature feature) => switch (feature) {
    AppTourFeature.signTranslate => '/sign-camera',
    AppTourFeature.speechToSign => '/speech-to-sign',
    AppTourFeature.twoWayDialogue => '/dialogue',
    AppTourFeature.signDictionary => '/sign-dictionary',
    AppTourFeature.requestHelp => '/assistance-request/new',
    AppTourFeature.queueTracking => '/queue',
    // SOS is explained on its existing Home button. This avoids starting an
    // emergency countdown just to show a coach mark.
    AppTourFeature.sos => '/home',
    AppTourFeature.complete => '/tour-complete',
  };

  Future<void> _complete() async {
    _isRunning = false;
    final shouldSaveCompletion = _shouldSaveCompletion;
    _guide = AppTourGuide.full;
    _shouldSaveCompletion = false;
    _currentFeature = null;
    _homeSection = null;
    _sosStep = 0;
    notifyListeners();
    if (!shouldSaveCompletion) return;
    try {
      await _repository.markHomeTourComplete();
    } catch (_) {
      // Completion persistence is best effort; a storage failure must not
      // leave the traveller stuck behind the final coach mark.
    }
  }
}
