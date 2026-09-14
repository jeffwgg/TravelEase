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
import 'announcement_text_refiner.dart';
import 'app_notification_service.dart';
import 'environment_sound_detector.dart';
import 'flash_alert_service.dart';

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
/// The environment-sound settings toggle ("Spoken Announcement" / public
/// announcement detection) controls whether the detector emits the triggering
/// alerts. Captures are available without an active venue session.
class PublicAnnouncementCaptureService {
  PublicAnnouncementCaptureService._();

  static final instance = PublicAnnouncementCaptureService._();

  /// A public-address message is often longer than a conversational turn.
  /// Keep a finite ceiling so a nearby conversation cannot hold the microphone
  /// indefinitely, but do not truncate normal airport or station messages.
  static const _maximumListenDuration = Duration(seconds: 55);

  /// The system speech recogniser finalises after this much silence. A short
  /// pause inside a multi-sentence announcement must not publish a fragment.
  static const _endOfAnnouncementSilence = Duration(milliseconds: 3500);

  /// Lets the recogniser return its final words when the maximum duration is
  /// reached before our defensive watchdog uses the best partial result.
  static const _maximumListenGrace = Duration(seconds: 2);
  static const _microphoneHandoffDelay = Duration(milliseconds: 100);

  /// Avoid immediately reopening the recogniser for the same spoken clip,
  /// while still allowing a retry when a first handoff produced no text.
  static const _successfulCaptureCooldown = Duration(seconds: 10);

  /// A recogniser that has stopped responding must not block all future
  /// announcements until the 55-second maximum session timeout.
  static const _firstResultTimeout = Duration(seconds: 6);
  static const _resultInactivityTimeout = Duration(seconds: 6);
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
  final stt.SpeechToText _speech = stt.SpeechToText();

  StreamSubscription<EnvironmentSoundDetection>? _alertSubscription;
  Timer? _listenTimeout;
  Completer<String?>? _activeListen;

  /// Recent below-threshold transcripts used for repetition matching.
  final List<_CandidateUtterance> _recentCandidates = [];

  /// Timestamps of recent chime/bell/alarm alerts (paging-tone context).
  final List<DateTime> _recentToneTimes = [];

  bool _capturing = false;
  bool _started = false;
  bool _speechInitialized = false;
  int _captureGeneration = 0;
  DateTime? _lastSuccessfulCaptureAt;

  void start() {
    if (_started) return;
    _started = true;
    _alertSubscription = _detector.alerts.listen(_onDetection);
  }

  Future<void> dispose() async {
    await cancelPendingCapture();
    await _alertSubscription?.cancel();
    _alertSubscription = null;
    _started = false;
  }

  /// Stops an in-flight automatic transcription immediately. This is called
  /// when the traveller turns off Spoken Announcement or all monitoring.
  Future<void> cancelPendingCapture() async {
    _captureGeneration++;
    _listenTimeout?.cancel();
    _listenTimeout = null;
    final activeListen = _activeListen;
    if (activeListen != null && !activeListen.isCompleted) {
      activeListen.complete(null);
    }
    try {
      await _speech.cancel();
    } catch (_) {
      // The recogniser may not have started yet.
    }
  }

  Future<void> _onDetection(EnvironmentSoundDetection detection) async {
    if (detection.type == EnvironmentSoundType.alarm ||
        detection.type == EnvironmentSoundType.doorbell) {
      _rememberTone();
      await _recheckRecentCandidateWithTone();
      return;
    }
    if (detection.type != EnvironmentSoundType.speechAnnouncement) return;
    if (_capturing || !await _spokenAnnouncementEnabled()) {
      return;
    }
    final now = DateTime.now();
    final lastCapture = _lastSuccessfulCaptureAt;
    if (lastCapture != null &&
        now.difference(lastCapture) < _successfulCaptureCooldown) {
      return;
    }
    _capturing = true;
    final captureGeneration = ++_captureGeneration;
    final pagedRecently = _hasRecentTone();
    final wasMonitoring = _detector.isMonitoring;
    try {
      // Hand the microphone over from the YAMNet classifier to the recogniser.
      if (wasMonitoring) await _detector.stop();
      // The classifier has already identified speech. Keep the handoff short
      // so short real-world PA clips still have enough spoken content left
      // for the platform recogniser to transcribe.
      await Future<void>.delayed(_microphoneHandoffDelay);
      if (captureGeneration != _captureGeneration ||
          !await _spokenAnnouncementEnabled()) {
        return;
      }
      final captured = await _capture(
        detection,
        pagingTone: pagedRecently,
        captureGeneration: captureGeneration,
      );
      if (captured) _lastSuccessfulCaptureAt = DateTime.now();
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

  Future<bool> _capture(
    EnvironmentSoundDetection detection, {
    required bool pagingTone,
    required int captureGeneration,
  }) async {
    var micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      micStatus = await Permission.microphone.request();
    }
    if (micStatus.isDenied || micStatus.isPermanentlyDenied) return false;

    if (captureGeneration != _captureGeneration ||
        !await _spokenAnnouncementEnabled()) {
      return false;
    }
    final transcript = await _recognise(captureGeneration);
    if (transcript == null) return false;
    final trimmed = transcript.trim();
    if (trimmed.length < _minTranscriptLength) return false;

    if (captureGeneration != _captureGeneration ||
        !await _spokenAnnouncementEnabled()) {
      return false;
    }

    final repetition = _countRepetition(trimmed);
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

    // Sound classification only establishes that there was speech, narration
    // or synthetic speech nearby. Keep an unverified transcript only for a
    // possible second-pass check; never publish it as an announcement.
    if (!result.isAnnouncement) {
      _rememberCandidate(trimmed, detection.score);
      return false;
    }

    final refinement = AnnouncementTextRefiner.formatLocally(trimmed);
    if (captureGeneration != _captureGeneration ||
        !await _spokenAnnouncementEnabled()) {
      return false;
    }

    final capture = await _mergeOrCapture(
      title: refinement.title,
      transcript: refinement.transcript,
      originalTranscript: trimmed,
      isAiRefined: false,
      confidence: result.confidence,
      detectionScore: detection.score,
      keywordHits: result.keywordHits,
      language: result.language,
    );

    await FlashAlertService.instance.blinkTwice();
    await AppNotificationService.instance.showCapturedAnnouncement(
      id: capture.id,
      title: capture.title,
      message: capture.transcript,
      confidencePercent: (capture.confidence * 100).round(),
    );
    return true;
  }

  /// English first (the primary PA language), then Bahasa Melayu. Returns the
  /// best transcript, or null when nothing usable was recognised.
  Future<bool> _ensureSpeechInitialized() async {
    if (_speechInitialized) return true;
    try {
      _speechInitialized = await _speech.initialize(
        onError: (error) =>
            debugPrint('[PublicAnnouncementCapture] STT error: $error'),
      );
      return _speechInitialized;
    } catch (error) {
      debugPrint('[PublicAnnouncementCapture] STT error: $error');
      return false;
    }
  }

  Future<String?> _recognise(int captureGeneration) async {
    if (!await _ensureSpeechInitialized()) return null;
    try {
      // Keep one recogniser alive for the app lifetime. Recreating it for
      // every sound event repeatedly wakes the platform microphone service.
      var text = await _listenOnce('en_US', captureGeneration);
      // Only retry Malay when English returned nothing. A second recognition
      // session is otherwise another unnecessary microphone activation.
      if (text == null && captureGeneration == _captureGeneration) {
        text = await _listenOnce('ms_MY', captureGeneration);
      }
      return text;
    } finally {
      try {
        await _speech.stop();
      } catch (_) {}
    }
  }

  Future<String?> _listenOnce(String localeId, int captureGeneration) async {
    final completer = Completer<String?>();
    var finalText = '';
    var bestPartial = '';
    Timer? firstResultTimeout;
    Timer? resultInactivityTimeout;
    _activeListen = completer;

    Future<void> finishWithBestText() async {
      if (completer.isCompleted) return;
      try {
        await _speech.stop();
      } catch (_) {}
      if (!completer.isCompleted) {
        completer.complete(
          captureGeneration == _captureGeneration
              ? (finalText.trim().isNotEmpty ? finalText : bestPartial)
              : null,
        );
      }
    }

    void resetInactivityTimeout() {
      firstResultTimeout?.cancel();
      resultInactivityTimeout?.cancel();
      resultInactivityTimeout = Timer(
        _resultInactivityTimeout,
        finishWithBestText,
      );
    }

    // Some Android recognisers return neither a result nor an error when the
    // microphone handoff races a short announcement. Release that stalled
    // attempt quickly so the next detected speech can retry.
    firstResultTimeout = Timer(_firstResultTimeout, finishWithBestText);

    try {
      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isEmpty) return;
          firstResultTimeout?.cancel();
          if (result.finalResult) {
            resultInactivityTimeout?.cancel();
            finalText = _mergeRecognitionText(bestPartial, words);
            if (!completer.isCompleted) completer.complete(finalText);
          } else {
            // Android can report a newer partial containing only the tail of
            // the utterance. Preserve the preceding words instead of letting
            // that shorter update overwrite the announcement heard so far.
            bestPartial = _mergeRecognitionText(bestPartial, words);
            resetInactivityTimeout();
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
          listenFor: _maximumListenDuration,
          pauseFor: _endOfAnnouncementSilence,
          localeId: localeId,
        ),
      );
    } catch (error) {
      debugPrint('[PublicAnnouncementCapture] STT listen error: $error');
      completer.complete(null);
    }

    // `pauseFor` makes the platform wait for a real quiet gap before emitting
    // a final result. `listenFor` protects against recognisers that otherwise
    // listen indefinitely. The watchdog is deliberately slightly longer, so
    // the plugin can return its final words rather than us saving a fragment.
    _listenTimeout = Timer(
      _maximumListenDuration + _maximumListenGrace,
      () async {
        if (completer.isCompleted) return;
        try {
          await _speech.stop();
        } catch (_) {}
        if (!completer.isCompleted) {
          completer.complete(
            captureGeneration == _captureGeneration
                ? (finalText.trim().isNotEmpty ? finalText : bestPartial)
                : null,
          );
        }
      },
    );

    try {
      return await completer.future;
    } finally {
      firstResultTimeout?.cancel();
      resultInactivityTimeout?.cancel();
      if (identical(_activeListen, completer)) _activeListen = null;
      _listenTimeout?.cancel();
      _listenTimeout = null;
    }
  }

  Future<bool> _spokenAnnouncementEnabled() async {
    final preferences = EnvironmentSoundPreferences();
    if (!await preferences.loadEnabled()) return false;
    return (await preferences.loadTypes()).contains(
      EnvironmentSoundType.speechAnnouncement,
    );
  }

  /// How many times a similar utterance was already heard on this device
  /// within the repetition window (recent candidates plus stored captures).
  int _countRepetition(String transcript) {
    var count = 0;
    final now = DateTime.now();
    for (final candidate in _recentCandidates) {
      if (now.difference(candidate.heardAt) > _repetitionWindow) continue;
      if (_isSimilar(transcript, candidate.normalizedTranscript)) count += 1;
    }
    return count + 1;
  }

  void _rememberCandidate(String transcript, double detectionScore) {
    final now = DateTime.now();
    _recentCandidates.removeWhere(
      (candidate) => now.difference(candidate.heardAt) > _repetitionWindow,
    );
    final existing = _recentCandidates.where(
      (candidate) => _isSimilar(transcript, candidate.normalizedTranscript),
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
    if (_capturing) return;
    final now = DateTime.now();
    _recentCandidates.removeWhere(
      (candidate) => now.difference(candidate.heardAt) > _toneRecheckWindow,
    );
    if (_recentCandidates.isEmpty) return;
    final candidate = _recentCandidates.last;

    _capturing = true;
    try {
      final repetition = _countRepetition(candidate.transcript);
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
      final refinement = AnnouncementTextRefiner.formatLocally(
        candidate.transcript,
      );
      final capture = await _mergeOrCapture(
        title: refinement.title,
        transcript: refinement.transcript,
        originalTranscript: candidate.transcript,
        isAiRefined: false,
        confidence: result.confidence,
        detectionScore: candidate.detectionScore,
        keywordHits: result.keywordHits,
        language: result.language,
      );
      await FlashAlertService.instance.blinkTwice();
      await AppNotificationService.instance.showCapturedAnnouncement(
        id: capture.id,
        title: capture.title,
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
    required String title,
    required String transcript,
    required String originalTranscript,
    required bool isAiRefined,
    required double confidence,
    required double detectionScore,
    required int keywordHits,
    required String language,
  }) async {
    final now = DateTime.now();
    final existing = await _store.all();
    for (final entry in existing) {
      if (now.difference(entry.lastCapturedAt) > _repetitionWindow) continue;
      if (!_isSimilar(transcript, entry.transcript)) continue;
      final useNewTranscript = transcript.length >= entry.transcript.length;
      final merged = CapturedAnnouncement(
        id: entry.id,
        institutionId: entry.institutionId,
        title: useNewTranscript ? title : entry.title,
        transcript: useNewTranscript ? transcript : entry.transcript,
        originalTranscript: useNewTranscript
            ? originalTranscript
            : entry.originalTranscript,
        isAiRefined: useNewTranscript ? isAiRefined : entry.isAiRefined,
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
      title: title,
      transcript: transcript,
      originalTranscript: originalTranscript,
      isAiRefined: isAiRefined,
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

  /// Combines progressive recogniser updates. Some Android recognisers send
  /// the whole phrase on each update, while others send only a new tail; this
  /// accepts either form and removes the shared word overlap.
  String _mergeRecognitionText(String existing, String incoming) {
    final current = existing.trim();
    final next = incoming.trim();
    if (current.isEmpty) return next;
    if (next.isEmpty) return current;

    final currentWords = current.split(RegExp(r'\s+'));
    final nextWords = next.split(RegExp(r'\s+'));
    final normalizedCurrent = currentWords
        .map(_normaliseRecognitionWord)
        .toList(growable: false);
    final normalizedNext = nextWords
        .map(_normaliseRecognitionWord)
        .toList(growable: false);

    if (_containsWordSequence(normalizedNext, normalizedCurrent)) return next;
    if (_containsWordSequence(normalizedCurrent, normalizedNext))
      return current;
    // Repeated PA recordings often restart immediately after the final
    // sentence. Treat a tail-to-opening update as the same circular
    // utterance, not text that should be appended in reverse order.
    if (_containsCircularWordSequence(normalizedCurrent, normalizedNext)) {
      return current;
    }
    if (_containsCircularWordSequence(normalizedNext, normalizedCurrent)) {
      return next;
    }

    var overlap = 0;
    final maximumOverlap = math.min(currentWords.length, nextWords.length);
    for (var size = maximumOverlap; size > 0; size--) {
      var matches = true;
      for (var index = 0; index < size; index++) {
        if (normalizedCurrent[currentWords.length - size + index] !=
            normalizedNext[index]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        overlap = size;
        break;
      }
    }
    return '$current ${nextWords.skip(overlap).join(' ')}'.trim();
  }

  String _normaliseRecognitionWord(String word) =>
      word.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  bool _containsWordSequence(List<String> text, List<String> sequence) {
    if (sequence.length > text.length) return false;
    for (var start = 0; start <= text.length - sequence.length; start++) {
      var matches = true;
      for (var offset = 0; offset < sequence.length; offset++) {
        if (text[start + offset] != sequence[offset]) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }
    return false;
  }

  bool _containsCircularWordSequence(List<String> text, List<String> sequence) {
    if (text.isEmpty || sequence.isEmpty || sequence.length > text.length) {
      return false;
    }
    return _containsWordSequence([...text, ...text], sequence);
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
  final double detectionScore;
  DateTime heardAt;

  _CandidateUtterance({
    required this.transcript,
    required this.normalizedTranscript,
    required this.detectionScore,
    required this.heardAt,
  });
}
