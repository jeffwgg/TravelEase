import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/entities/captured_announcement.dart';
import '../models/entities/environment_sound.dart';
import '../models/repositories/captured_announcement_store.dart';
import '../models/repositories/environment_sound_repository.dart';
import 'announcement_keyword_scorer.dart';
import 'app_notification_service.dart';
import 'environment_sound_detector.dart';
import 'flash_alert_service.dart';
import 'venue_session_service.dart';

/// Captures public-address announcements from the environment (FR-M2-08).
///
/// Pipeline: the YAMNet sound detector flags speech on a public-address
/// system, the microphone is handed over to the speech recogniser (English,
/// falling back to Bahasa Melayu), the transcript is scored for announcement
/// phrasing, and recognised captures join the announcement list labelled
/// "Captured" with a confidence score (FR-M2-09). Repetition counts as a
/// signal because PA announcements are typically played twice. The score is
/// advisory: once the sound model has identified PA-style speech, a usable
/// transcript is shown even when it contains no predefined travel keyword.
///
/// Paging-tone condition: PA systems play a chime, bell or alarm tone around
/// the spoken message. A tone heard shortly before the speech relaxes the
/// keyword gate, and a tone heard shortly after a failed transcript re-checks
/// that transcript with the tone as extra evidence.
///
/// Runs only while a venue session is active; the environment-sound settings
/// toggle ("Spoken Announcement" / public announcement detection) controls
/// whether the detector emits the triggering alerts at all.
class PublicAnnouncementCaptureService {
  PublicAnnouncementCaptureService._();

  static final instance = PublicAnnouncementCaptureService._();

  static const _listenDuration = Duration(seconds: 20);
  static const _microphoneHandoffDelay = Duration(milliseconds: 100);
  static const _repetitionWindow = Duration(minutes: 5);
  static const _minTranscriptLength = 12;

  /// How recent a chime/bell/alarm alert must be to count as paging-tone
  /// context for a speech detection.
  static const _toneWindow = Duration(seconds: 15);

  /// How old a failed candidate may be for a tone-triggered re-check.
  static const _toneRecheckWindow = Duration(seconds: 20);

  final EnvironmentSoundDetector _detector = EnvironmentSoundDetector();
  final AnnouncementKeywordScorer _scorer = const AnnouncementKeywordScorer();
  final CapturedAnnouncementStore _store = CapturedAnnouncementStore.instance;

  StreamSubscription<EnvironmentSoundDetection>? _alertSubscription;

  /// Recent below-threshold transcripts used for repetition matching.
  final List<_CandidateUtterance> _recentCandidates = [];

  /// Timestamps of recent chime/bell/alarm alerts (paging-tone context).
  final List<DateTime> _recentToneTimes = [];

  bool _capturing = false;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _alertSubscription = _detector.alerts.listen(_onDetection);
  }

  Future<void> dispose() async {
    await _alertSubscription?.cancel();
    _alertSubscription = null;
    _started = false;
  }

  Future<void> _onDetection(EnvironmentSoundDetection detection) async {
    if (detection.type == EnvironmentSoundType.alarm ||
        detection.type == EnvironmentSoundType.doorbell) {
      _rememberTone();
      await _recheckRecentCandidateWithTone();
      return;
    }
    if (detection.type != EnvironmentSoundType.speechAnnouncement) return;
    if (_capturing || !VenueSessionService.instance.hasActiveSession) return;
    _capturing = true;
    final pagedRecently = _hasRecentTone();
    final wasMonitoring = _detector.isMonitoring;
    try {
      // Hand the microphone over from the YAMNet classifier to the recogniser.
      if (wasMonitoring) await _detector.stop();
      // The classifier has already identified speech. Keep the handoff short
      // so short real-world PA clips still have enough spoken content left
      // for the platform recogniser to transcribe.
      await Future<void>.delayed(_microphoneHandoffDelay);
      await _capture(detection, pagingTone: pagedRecently);
    } catch (error) {
      debugPrint('[PublicAnnouncementCapture] failed: $error');
    } finally {
      _capturing = false;
      if (wasMonitoring) await _restartDetector();
    }
  }

  void _rememberTone() {
    final now = DateTime.now();
    _recentToneTimes.removeWhere(
      (time) => now.difference(time) > _toneRecheckWindow,
    );
    _recentToneTimes.add(now);
  }

  bool _hasRecentTone() {
    final now = DateTime.now();
    _recentToneTimes.removeWhere((time) => now.difference(time) > _toneWindow);
    return _recentToneTimes.isNotEmpty;
  }

  Future<void> _capture(
    EnvironmentSoundDetection detection, {
    required bool pagingTone,
  }) async {
    final micStatus = await Permission.microphone.request();
    if (micStatus.isDenied || micStatus.isPermanentlyDenied) return;

    final transcript = await _recognise();
    if (transcript == null) return;
    final trimmed = transcript.trim();
    if (trimmed.length < _minTranscriptLength) return;

    final institutionId = VenueSessionService.instance.session?.institutionId;
    if (institutionId == null) return;

    final repetition = _countRepetition(trimmed, institutionId);
    final result = _scorer.score(
      trimmed,
      detection.score,
      repetitionCount: repetition,
      pagingTone: pagingTone,
    );
    debugPrint(
      '[PublicAnnouncementCapture] "${trimmed.substring(0, math.min(60, trimmed.length))}" '
      'conf=${result.confidence.toStringAsFixed(2)} kw=${result.keywordScore.toStringAsFixed(2)} '
      'rep=$repetition tone=$pagingTone valid=${result.isAnnouncement}',
    );

    // Keep below-threshold text as a repetition/tone candidate, but do not
    // hide the transcript. A real announcement can contain names, local
    // wording or instructions that are absent from the keyword dictionary.
    if (!result.isAnnouncement) {
      _rememberCandidate(trimmed, detection.score, institutionId);
    }

    final capture = await _mergeOrCapture(
      transcript: trimmed,
      institutionId: institutionId,
      confidence: result.confidence,
      detectionScore: detection.score,
      keywordHits: result.keywordHits,
      language: result.language,
    );

    await FlashAlertService.instance.blinkTwice();
    await AppNotificationService.instance.showCapturedAnnouncement(
      id: capture.id,
      title: 'Public announcement captured',
      message: capture.transcript,
      confidencePercent: (capture.confidence * 100).round(),
    );
  }

  /// English first (the primary PA language), then Bahasa Melayu. Returns the
  /// best transcript, or null when nothing usable was recognised.
  Future<String?> _recognise() async {
    final speech = stt.SpeechToText();
    try {
      if (!await speech.initialize()) return null;
      var text = await _listenOnce(speech, 'en_US');
      if (text == null || text.trim().length < _minTranscriptLength) {
        final malay = await _listenOnce(speech, 'ms_MY');
        if (malay != null && malay.trim().length > (text?.trim().length ?? 0)) {
          text = malay;
        }
      }
      return text;
    } catch (error) {
      debugPrint('[PublicAnnouncementCapture] STT error: $error');
      return null;
    } finally {
      try {
        await speech.cancel();
        await speech.stop();
      } catch (_) {}
    }
  }

  Future<String?> _listenOnce(stt.SpeechToText speech, String localeId) {
    final completer = Completer<String?>();
    var finalText = '';
    var bestPartial = '';

    speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          finalText = result.recognizedWords;
          if (!completer.isCompleted) completer.complete(finalText);
        } else {
          bestPartial = result.recognizedWords;
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
        localeId: localeId,
      ),
    );

    // Public-address announcements run longer than conversation turns, so a
    // generous window is used; stop() finalises whatever was recognised.
    Timer(_listenDuration, () async {
      if (completer.isCompleted) return;
      try {
        await speech.stop();
      } catch (_) {}
      if (!completer.isCompleted) {
        completer.complete(
          finalText.trim().isNotEmpty ? finalText : bestPartial,
        );
      }
    });

    return completer.future;
  }

  /// How many times a similar utterance was already heard for this venue
  /// within the repetition window (recent candidates plus stored captures).
  int _countRepetition(String transcript, String institutionId) {
    var count = 0;
    final now = DateTime.now();
    for (final candidate in _recentCandidates) {
      if (candidate.institutionId != institutionId) continue;
      if (now.difference(candidate.heardAt) > _repetitionWindow) continue;
      if (_isSimilar(transcript, candidate.normalizedTranscript)) count += 1;
    }
    return count + 1;
  }

  void _rememberCandidate(
    String transcript,
    double detectionScore,
    String institutionId,
  ) {
    final now = DateTime.now();
    _recentCandidates.removeWhere(
      (candidate) => now.difference(candidate.heardAt) > _repetitionWindow,
    );
    final existing = _recentCandidates.where(
      (candidate) =>
          candidate.institutionId == institutionId &&
          _isSimilar(transcript, candidate.normalizedTranscript),
    );
    if (existing.isNotEmpty) {
      existing.first.heardAt = now;
      return;
    }
    _recentCandidates.add(
      _CandidateUtterance(
        transcript: transcript,
        normalizedTranscript: _normalize(transcript),
        heardAt: now,
        institutionId: institutionId,
        detectionScore: detectionScore,
      ),
    );
    while (_recentCandidates.length > 10) {
      _recentCandidates.removeAt(0);
    }
  }

  /// Speech → tone order: PA systems often play the chime after (or over the
  /// tail of) the spoken message. When a paging tone arrives shortly after a
  /// transcript failed the keyword gate, re-evaluate that transcript with the
  /// tone as extra evidence.
  Future<void> _recheckRecentCandidateWithTone() async {
    if (_capturing || !VenueSessionService.instance.hasActiveSession) return;
    final now = DateTime.now();
    _recentCandidates.removeWhere(
      (candidate) => now.difference(candidate.heardAt) > _toneRecheckWindow,
    );
    if (_recentCandidates.isEmpty) return;
    final candidate = _recentCandidates.last;

    _capturing = true;
    try {
      final repetition = _countRepetition(
        candidate.transcript,
        candidate.institutionId,
      );
      final result = _scorer.score(
        candidate.transcript,
        candidate.detectionScore,
        repetitionCount: repetition,
        pagingTone: true,
      );
      debugPrint(
        '[PublicAnnouncementCapture] tone re-check "${candidate.transcript.substring(0, math.min(60, candidate.transcript.length))}" '
        'conf=${result.confidence.toStringAsFixed(2)} kw=${result.keywordScore.toStringAsFixed(2)} '
        'valid=${result.isAnnouncement}',
      );
      if (!result.isAnnouncement) return;
      _recentCandidates.remove(candidate);
      final capture = await _mergeOrCapture(
        transcript: candidate.transcript,
        institutionId: candidate.institutionId,
        confidence: result.confidence,
        detectionScore: candidate.detectionScore,
        keywordHits: result.keywordHits,
        language: result.language,
      );
      await FlashAlertService.instance.blinkTwice();
      await AppNotificationService.instance.showCapturedAnnouncement(
        id: capture.id,
        title: 'Public announcement captured',
        message: capture.transcript,
        confidencePercent: (capture.confidence * 100).round(),
      );
    } catch (error) {
      debugPrint('[PublicAnnouncementCapture] tone re-check failed: $error');
    } finally {
      _capturing = false;
    }
  }

  /// Merges with a recently stored capture of the same announcement, or
  /// creates a new stored capture.
  Future<CapturedAnnouncement> _mergeOrCapture({
    required String transcript,
    required String institutionId,
    required double confidence,
    required double detectionScore,
    required int keywordHits,
    required String language,
  }) async {
    final now = DateTime.now();
    final existing = await _store.forVenue(institutionId);
    for (final entry in existing) {
      if (now.difference(entry.lastCapturedAt) > _repetitionWindow) continue;
      if (!_isSimilar(transcript, entry.transcript)) continue;
      final merged = CapturedAnnouncement(
        id: entry.id,
        institutionId: entry.institutionId,
        transcript: transcript.length >= entry.transcript.length
            ? transcript
            : entry.transcript,
        language: language,
        confidence: math.max(confidence, entry.confidence),
        detectionScore: math.max(detectionScore, entry.detectionScore),
        keywordHits: math.max(keywordHits, entry.keywordHits),
        repetitionCount: entry.repetitionCount + 1,
        firstCapturedAt: entry.firstCapturedAt,
        lastCapturedAt: now,
      );
      await _store.upsert(merged);
      return merged;
    }

    final capture = CapturedAnnouncement(
      id: _newId(),
      institutionId: institutionId,
      transcript: transcript,
      language: language,
      confidence: confidence,
      detectionScore: detectionScore,
      keywordHits: keywordHits,
      repetitionCount: 1,
      firstCapturedAt: now,
      lastCapturedAt: now,
    );
    await _store.upsert(capture);
    return capture;
  }

  /// Word-overlap similarity used for the "announced twice" heuristic.
  bool _isSimilar(String a, String b) {
    final wordsA = _normalize(a).split(' ').toSet();
    final wordsB = _normalize(b).split(' ').toSet();
    if (wordsA.isEmpty || wordsB.isEmpty) return false;
    final intersection = wordsA.intersection(wordsB).length;
    final union = wordsA.union(wordsB).length;
    return union > 0 && intersection / union >= 0.6;
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _newId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'cap-$now-${math.Random().nextInt(0x7fffffff)}';
  }

  Future<void> _restartDetector() async {
    final preferences = EnvironmentSoundPreferences();
    try {
      if (!await preferences.loadEnabled()) return;
      final types = await preferences.loadTypes();
      if (types.isEmpty) return;
      await _detector.start(
        enabledTypes: types,
        sensitivity: await preferences.loadSensitivity(),
      );
    } catch (_) {
      // Restarting the ambient sound detector is best-effort.
    }
  }
}

class _CandidateUtterance {
  final String transcript;
  final String normalizedTranscript;
  final String institutionId;
  final double detectionScore;
  DateTime heardAt;

  _CandidateUtterance({
    required this.transcript,
    required this.normalizedTranscript,
    required this.institutionId,
    required this.detectionScore,
    required this.heardAt,
  });
}
