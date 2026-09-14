import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'sign_frame_data.dart';

/// A recorded clip of one sign performance.
class SignClip {
  final String label;
  final List<SignFrameData> frames;
  SignClip({required this.label, required this.frames});

  Map<String, dynamic> toJson() => {
        'label': label,
        'frames': frames.map((f) => f.toJson()).toList(),
      };

  static SignClip fromJson(Map<String, dynamic> j) => SignClip(
        label: j['label'] as String,
        frames: (j['frames'] as List)
            .map((f) => SignFrameData.fromJson((f as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// In-memory recorder for labelled sign clips (accuracy harness, Phase 0.2).
///
/// Clips live for the current app session. Use [exportJson] /
/// [copyToClipboard] to persist a session, then paste into
/// `test/fixtures/sign_clips.json` for regression testing.
class SignClipRecorder {
  final List<SignClip> _clips = [];
  SignClip? _active;
  SignFrameData? _pending;

  bool get isRecording => _active != null;
  String? get activeLabel => _active?.label;
  int get clipCount => _clips.length;
  int get activeFrameCount => _active?.frames.length ?? 0;

  /// Stage a frame; committed to the active clip on [commitPendingFrame] or
  /// clip end. (Lets the extractor offer the frame before deciding.)
  void stageFrame(SignFrameData frame) => _pending = frame;

  void startClip(String label) {
    endClip();
    _active = SignClip(label: label, frames: []);
    if (_pending != null) _active!.frames.add(_pending!);
  }

  /// Appends the latest staged frame to the active clip.
  void addFrame(SignFrameData frame) => _active?.frames.add(frame);

  /// Batch capture: append a complete, already-segmented clip directly
  /// (used by batch recording where the motion gate supplies each gesture's
  /// frames). Bypasses the manual start/end session flow. Returns the running
  /// clip count for this label.
  int captureClip(String label, List<SignFrameData> frames) {
    if (label.trim().isEmpty || frames.length < 5) return clipCount;
    _clips.add(SignClip(label: label.trim().toLowerCase(), frames: frames));
    return clipCount;
  }

  int countFor(String label) => _clips
      .where((c) => c.label == label.trim().toLowerCase())
      .length;

  SignClip? endClip() {
    final c = _active;
    if (c != null && c.frames.isNotEmpty) _clips.add(c);
    _active = null;
    return (c != null && c.frames.isNotEmpty) ? c : null;
  }

  String exportJson() {
    endClip();
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'clips': _clips.map((c) => c.toJson()).toList(),
    });
  }

  /// Copies the session JSON to the clipboard. Returns clip count.
  ///
  /// NOTE: the Android clipboard silently drops large text (especially on
  /// Huawei OEM builds) — prefer [exportToFile] + the share sheet.
  Future<int> copyToClipboard() async {
    final n = _clips.length;
    await Clipboard.setData(ClipboardData(text: exportJson()));
    return n;
  }

  /// Writes the session JSON to the app's external files dir and returns the
  /// path — shareable via the system sheet and reachable from a PC with
  /// `adb pull`. The clipboard is too small for multi-minute recordings.
  Future<String> exportToFile() async {
    final name = 'bim_clips_${DateTime.now().millisecondsSinceEpoch}.json';
    final dir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsString(exportJson());
    return f.path;
  }

  void clear() {
    _clips.clear();
    _active = null;
    _pending = null;
  }
}
