import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// TEMPORARY diagnostics screen.
///
/// Reports the ACTUAL Mandarin speech capabilities exposed by this device:
///   1. System TTS engines + languages (what flutter_tts can reach).
///   2. System speech recognition locales (what speech_to_text can reach).
///   3. The OS-configured default engines.
///   4. Installed Huawei packages (HMS Core, Celia Keyboard, AI Voice...).
///   5. Live speak / listen probes in Mandarin.
///
/// Everything is also printed via debugPrint so `flutter logs` / the IDE
/// console shows the raw values. Remove this screen once the Mandarin
/// strategy is confirmed.
class SpeechDiagnosticsView extends StatefulWidget {
  const SpeechDiagnosticsView({super.key});

  @override
  State<SpeechDiagnosticsView> createState() => _SpeechDiagnosticsViewState();
}

class _SpeechDiagnosticsViewState extends State<SpeechDiagnosticsView> {
  static const _envChannel = MethodChannel('travelease/speech_env');

  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _running = true;
  String _log = '';

  // ---- Native environment -------------------------------------------------
  Map<String, dynamic>? _native;
  // ---- TTS ----------------------------------------------------------------
  List<String> _ttsEngines = [];
  String? _defaultTtsEngine;
  String? _defaultVoice;
  List<String> _ttsLanguages = [];
  final Map<String, String?> _ttsChecks = {};
  final List<String> _zhVoices = [];
  String? _speakProbeResult;
  // ---- STT ----------------------------------------------------------------
  bool? _sttDefaultAvailable;
  bool? _sttIntentLookupAvailable;
  List<stt.LocaleName> _sttLocales = [];
  stt.LocaleName? _systemLocale;
  String _listenProbeResult = '';
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _runAll();
  }

  Future<T> _guard<T>(Future<T> Function() body, T fallback,
      {int seconds = 8}) async {
    try {
      return await body().timeout(Duration(seconds: seconds));
    } catch (e) {
      _logLine('  !! ${e.runtimeType}: $e');
      return fallback;
    }
  }

  void _logLine(String line) {
    debugPrint('[SpeechDiag] $line');
    if (mounted && _log.length < 60000) _log = '$_log\n$line';
  }

  Future<void> _runAll() async {
    setState(() => _running = true);
    await _probeNative();
    await _probeTts();
    await _probeStt();
    _logVerdict();
    if (mounted) setState(() => _running = false);
  }

  // --------------------------------------------------------------------------
  // Native OS environment
  // --------------------------------------------------------------------------
  Future<void> _probeNative() async {
    _logLine('--- Native environment ---');
    final res = await _guard<Map<String, dynamic>>(
      () async =>
          Map<String, dynamic>.from(await _envChannel.invokeMethod('getSpeechEnvironment')),
      <String, dynamic>{},
    );
    _native = res.isEmpty ? null : res;
    if (_native != null) {
      for (final entry in _native!.entries) {
        _logLine('native.${entry.key} = ${entry.value}');
      }
    } else {
      _logLine('native channel unavailable');
    }
  }

  // --------------------------------------------------------------------------
  // TTS (Android TextToSpeech layer used by flutter_tts)
  // --------------------------------------------------------------------------
  Future<void> _probeTts() async {
    _logLine('--- TTS (flutter_tts) ---');

    _ttsEngines =
        await _guard(() async => List<String>.from((await _tts.getEngines) ?? []),
            <String>[], seconds: 10);
    _logLine('tts.engines = $_ttsEngines');

    _defaultTtsEngine = await _guard(() async => (await _tts.getDefaultEngine) as String?,
        null, seconds: 10);
    _logLine('tts.defaultEngine = $_defaultTtsEngine');

    try {
      final voices = await _guard(() async => (await _tts.getVoices) ?? [], [], seconds: 10);
      for (final v in voices) {
        final locale = (v as Map)['locale']?.toString().toLowerCase() ?? '';
        if (locale.startsWith('zh') || locale.contains('-cn')) {
          _zhVoices.add(v.toString());
        }
      }
      _logLine('tts.chineseVoices = $_zhVoices');
    } catch (_) {}

    _defaultVoice = await _guard(() async => (await _tts.getDefaultVoice)?.toString(), null);
    _logLine('tts.defaultVoice = $_defaultVoice');

    _ttsLanguages = await _guard(
        () async => List<String>.from((await _tts.getLanguages) ?? []),
        <String>[],
        seconds: 12);
    _logLine('tts.languages (${_ttsLanguages.length}) = $_ttsLanguages');

    const candidates = ['zh-CN', 'zh-Hans', 'zh', 'zh-TW', 'zh-HK', 'zh-SG', 'ms-MY', 'en-US'];
    for (final lang in candidates) {
      final available =
          await _guard(() async => (await _tts.isLanguageAvailable(lang)) == true, false);
      final installed = available
          ? null
          : await _guard(
              () async => (await _tts.isLanguageInstalled(lang)) == true, false);
      _ttsChecks[lang] = available == true
          ? 'available'
          : (installed == true ? 'installed-not-listed' : 'NO');
      _logLine("tts.isLanguageAvailable($lang) -> ${_ttsChecks[lang]}");
    }
  }

  Future<void> _probeSpeakZh() async {
    setState(() => _speakProbeResult = 'speaking...');
    var result1 = await _guard(() => _tts.setLanguage('zh-CN'), -99);
    if ((result1 is int && result1 >= 0)) {
      _logLine('probe.setLanguage(zh-CN) = $result1');
    } else {
      result1 = await _guard(() => _tts.setLanguage('zh'), -99);
      _logLine('probe.setLanguage(zh) = $result1');
    }
    final ok = await _guard(() => _tts.speak('你好，欢迎使用我们的应用'), -1, seconds: 20);
    _logLine('probe.speak(zh) = $ok');
    if (mounted) setState(() => _speakProbeResult = '$ok');
  }

  // --------------------------------------------------------------------------
  // STT (android.speech.SpeechRecognizer layer used by speech_to_text)
  // --------------------------------------------------------------------------
  Future<void> _probeStt() async {
    _logLine('--- STT (speech_to_text) ---');

    _sttDefaultAvailable = await _guard<bool>(() async {
      return _speech.initialize(
        onStatus: (s) => _logLine('stt.status(default) = $s'),
        onError: (e) => _logLine('stt.error(default) = ${e.errorMsg}'),
        finalTimeout: const Duration(seconds: 3),
      );
    }, false, seconds: 12);
    _logLine('stt.initialize(default lookup) = $_sttDefaultAvailable');

    if (_sttDefaultAvailable != true) {
      _sttIntentLookupAvailable = await _guard<bool>(() async {
        return _speech.initialize(
          onStatus: (s) => _logLine('stt.status(intentLookup) = $s'),
          onError: (e) => _logLine('stt.error(intentLookup) = ${e.errorMsg}'),
          options: [stt.SpeechToText.androidIntentLookup],
          finalTimeout: const Duration(seconds: 3),
        );
      }, false, seconds: 12);
      _logLine('stt.initialize(androidIntentLookup) = $_sttIntentLookupAvailable');
    }

    _systemLocale = await _guard(() => _speech.systemLocale(), null, seconds: 8);
    _logLine('stt.systemLocale = $_systemLocale');

    _sttLocales = await _guard(() => _speech.locales(), <stt.LocaleName>[],
        seconds: 15);
    _logLine('stt.locales (${_sttLocales.length}): '
        '${_sttLocales.map((l) => l.localeId).join(", ")}');

    final ids = _sttLocales.map((l) => l.localeId.toLowerCase()).toList();
    _sttChecksSummary = {
      'zh-CN listed': ids.contains('zh_cn') || ids.contains('zh-cn'),
      'any zh_* listed': ids.any((id) => id.startsWith('zh')),
      'ms_MY listed': ids.contains('ms_my') || ids.contains('ms-my'),
    };
    _logLine('stt.zh checks = $_sttChecksSummary');
  }

  Map<String, bool>? _sttChecksSummary;

  Future<void> _probeListenZh() async {
    setState(() {
      _listenProbeResult = 'listening…';
      _listening = true;
    });
    final ids = _sttLocales.map((l) => l.localeId).toList();
    final locale = ids.firstWhere(
      (id) => id.toLowerCase() == 'zh_cn' || id.toLowerCase() == 'zh-cn',
      orElse: () => ids.firstWhere(
        (id) => id.toLowerCase().startsWith('zh'),
        orElse: () => 'zh-CN',
      ),
    );
    _logLine('probe.listen locale = $locale');
    await _speech.listen(
      onResult: (r) {
        _logLine('probe.listen result(final=${r.finalResult}) = "${r.recognizedWords}"');
        if (mounted) setState(() => _listenProbeResult = r.recognizedWords);
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.search,
        partialResults: true,
        cancelOnError: true,
        localeId: locale,
      ),
    );
    Future.delayed(const Duration(seconds: 9), () async {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
    });
  }

  // --------------------------------------------------------------------------
  // Verdict
  // --------------------------------------------------------------------------
  void _logVerdict() {
    bool anyTtsZh = _ttsChecks.entries
        .where((e) => e.key.startsWith('zh'))
        .any((e) => e.value != null && e.value != 'NO');
    bool anySttZh = _sttChecksSummary?['any zh_* listed'] ?? false;
    final hms = _hmsCoreInfo();
    _logLine('--- VERDICT ---');
    _logLine('B. system TTS Mandarin   : ${anyTtsZh ? "LIKELY AVAILABLE" : "NOT EXPOSED"}');
    _logLine('B. system ASR Mandarin   : '
        '${(_sttDefaultAvailable == true || _sttIntentLookupAvailable == true)
            ? (anySttZh ? "AVAILABLE" : "RECOGNIZER OK, zh NOT LISTED") : "UNAVAILABLE"}');
    _logLine('C. HMS Core installed    : ${hms != null
        ? "YES (${hms['versionName']}) - ML Kit viable"
        : "NOT DETECTED"}');
  }

  Map<String, dynamic>? _packageInfo(String name) {
    final packages = _native?['packages'];
    if (packages is Map && packages[name] is Map) {
      return Map<String, dynamic>.from(packages[name] as Map);
    }
    return null;
  }

  /// HMS Core ships under different package names across builds; detect by
  /// label as a last resort.
  Map<String, dynamic>? _hmsCoreInfo() {
    for (final name in ['com.huawei.android.hwid', 'com.huawei.hwid']) {
      final info = _packageInfo(name);
      if (info?['installed'] == true) return info;
    }
    final packages = _native?['packages'];
    if (packages is Map) {
      for (final entry in packages.entries) {
        final info = entry.value;
        if (info is Map &&
            info['installed'] == true &&
            '${info['label']}'.toLowerCase().contains('hms core')) {
          return Map<String, dynamic>.from(info);
        }
      }
    }
    return null;
  }

  // --------------------------------------------------------------------------
  // UI helpers
  // --------------------------------------------------------------------------
  Widget _card({required String title, required List<Widget> children}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, Object? v, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 190,
              child: Text(k,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          Expanded(
            child: SelectableText('$v',
                style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final native = _native;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Speech Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-run',
            onPressed: _running ? null : _runAll,
          ),
        ],
      ),
      body: _running && native == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _card(
                  title: 'Device',
                  children: [
                    if (native != null) ...[
                      _kv('model', native['deviceModel']),
                      _kv('product', native['deviceProduct']),
                      _kv('os', '${native['osRelease']} (SDK ${native['osSdkInt']})'),
                      if (native['harmonyVersion'] != null)
                        _kv('harmony property', native['harmonyVersion']),
                    ] else
                      const Text('native channel not available',
                          style: TextStyle(color: Colors.red)),
                  ],
                ),
                _card(
                  title: 'B — System TTS (flutter_tts)',
                  children: [
                    _kv('engines', _ttsEngines.isEmpty ? '(none returned)' : _ttsEngines.join(', ')),
                    _kv('default engine', _defaultTtsEngine ?? '(unknown)'),
                    _kv('default voice', _defaultVoice ?? '(unknown)'),
                    _kv('languages (${_ttsLanguages.length})',
                        _ttsLanguages.isEmpty ? '(none returned)' : _ttsLanguages.join(', ')),
                    ..._ttsChecks.entries.map((e) => _kv(
                        'isLanguageAvailable(${e.key})', e.value,
                        color: e.key.startsWith('zh') && e.value != 'NO'
                            ? Colors.green.shade700
                            : (e.key.startsWith('zh') ? Colors.red : null))),
                    if (_zhVoices.isNotEmpty)
                      _kv('Chinese voices', _zhVoices.join('\n')),
                    const Divider(),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      OutlinedButton(
                        onPressed: _probeSpeakZh,
                        child: const Text('🔊 Speak 你好，欢迎使用我们的应用'),
                      ),
                      if (_speakProbeResult != null)
                        Chip(label: Text('result: $_speakProbeResult')),
                    ]),
                  ],
                ),
                _card(
                  title: 'B — System ASR (speech_to_text)',
                  children: [
                    _kv('initialize (default)', _sttDefaultAvailable),
                    if (_sttIntentLookupAvailable != null)
                      _kv('initialize (intentLookup)', _sttIntentLookupAvailable),
                    _kv('recognizer available (OS)', _native?['recognizerAvailable']),
                    _kv('default recognition service',
                        _native?['defaultRecognitionService'] ?? '(not configured)'),
                    _kv('system locale', _systemLocale?.localeId ?? '(unknown)'),
                    _kv('locales (${_sttLocales.length})',
                        _sttLocales.isEmpty
                            ? '(none returned)'
                            : _sttLocales.map((l) => l.localeId).join(', ')),
                    ...?_sttChecksSummary?.entries.map((e) => _kv(e.key, e.value,
                        color: e.key.contains('zh') && e.value
                            ? Colors.green.shade700
                            : null)),
                    const Divider(),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      OutlinedButton(
                        onPressed: _listening ? null : _probeListenZh,
                        child: const Text('🎙 Listen (Mandarin, 8s)'),
                      ),
                      if (_listenProbeResult.isNotEmpty)
                        Chip(label: Text(_listenProbeResult)),
                    ]),
                  ],
                ),
                _card(
                  title: 'Installed recognizers / TTS services (raw)',
                  children: [
                    _kv('RecognitionServices',
                        _servicesSummary(_native?['recognitionServices'])),
                    _kv('RecognizerActivities',
                        _servicesSummary(_native?['recognitionServices'], kind: 'activity')),
                    _kv('TtsServices', _servicesSummary(_native?['ttsServices'])),
                  ],
                ),
                _card(
                  title: 'A/C — Huawei components',
                  children: [
                    _kv('HMS Core', _hmsCoreInfo() ?? 'not installed',
                        color: _hmsCoreInfo() != null
                            ? Colors.green.shade700
                            : Colors.red),
                    _kv('AppGallery', _packageInfo('com.huawei.appmarket') ?? 'not installed'),
                    ...[
                      ('Celia Keyboard', 'com.baidu.input_huawei'),
                      ('SwiftKey', 'com.touchtype.swiftkey'),
                      ('AI Voice 小艺 (CN)', 'com.huawei.vassistant'),
                      ('Celia Assistant (intl)', 'com.huawei.hiassistantoversea'),
                    ].map((p) => _kv(p.$1, _packageInfo(p.$2) ?? 'not installed')),
                    const Divider(),
                    const Text(
                      'A = keyboard voice input only affects typing, NOT this app.\n'
                      'B = what the cards above report.\n'
                      'C = ML Kit needs HMS Core (see HMS Core row).',
                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
                _card(
                  title: 'Raw log',
                  children: [
                    SelectableText(_log.trim(),
                        style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  String _servicesSummary(Object? value, {String kind = 'service'}) {
    if (value is! List || value.isEmpty) return '(none found)';
    return value
        .whereType<Map>()
        .where((m) => kind == 'service' || m['kind'] == kind)
        .map((m) => '${m['label']} [${m['package']}]')
        .join('\n');
  }
}
