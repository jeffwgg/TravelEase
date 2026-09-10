import 'dart:convert';
import 'package:flutter/services.dart';
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
  Future<int> copyToClipboard() async {
    final n = _clips.length;
    await Clipboard.setData(ClipboardData(text: exportJson()));
    return n;
  }

  void clear() {
    _clips.clear();
    _active = null;
    _pending = null;
  }
}
