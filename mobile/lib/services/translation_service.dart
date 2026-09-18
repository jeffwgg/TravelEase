import 'package:flutter/foundation.dart';

import '../core/supabase_client.dart';

/// Translation uses the authenticated self-hosted LibreTranslate proxy.
///
/// Supported app language codes: 'en', 'ms', 'zh'.
class TranslationService {
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;
  TranslationService._internal();

  /// Detects supported languages locally without sending the text to a
  /// third-party translation provider.
  Future<String> detectLanguage(String text) {
    final trimmed = text.trim();
    return Future.value(trimmed.isEmpty ? 'en' : heuristicDetect(trimmed));
  }

  /// Offline fallback heuristic: Chinese script check + Malay/English marker words.
  static String heuristicDetect(String text) {
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(text)) return 'zh';
    final scores = _markerScores(text);
    if (scores[0] > scores[1]) return 'ms';
    return 'en';
  }

  /// Like [heuristicDetect] but returns null when the text does not clearly
  /// look like Malay or English (at least 2 distinct marker words). Used for
  /// mid-utterance locale switching so a few unknown/garbled words never
  /// abort an ongoing recognition.
  static String? heuristicDetectConfident(String text) {
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(text)) return 'zh';
    final scores = _markerScores(text);
    if (scores[0] >= 2 && scores[0] > scores[1]) return 'ms';
    if (scores[1] >= 2 && scores[1] > scores[0]) return 'en';
    return null;
  }

  /// Returns [msScore, enScore] using whole-word matching so substrings
  /// (e.g. 'hi' inside 'sini') never count towards a language.
  static List<int> _markerScores(String text) {
    const msMarkers = [
      'saya', 'awak', 'kamu', 'anda', 'kami', 'kita', 'mana', 'apa', 'nak',
      'mahu', 'mau', 'tak', 'takut', 'tidak', 'terima', 'kasih', 'boleh',
      'tolong', 'ini', 'itu', 'untuk', 'dengan', 'sini', 'situ', 'sana',
      'sejuk', 'panas', 'macam', 'kerana', 'juga', 'sudah', 'dah', 'belum',
      'banyak', 'pergi', 'datang', 'bilik', 'tandas', 'makan', 'minum',
      'habis', 'jangan', 'bagaimana', 'kenapa', 'semua', 'orang', 'rumah',
      'jalan', 'sekarang', 'nanti', 'lapangan', 'terbang', 'bila', 'siapa',
      'saja', 'jom', 'kena', 'hantar', 'cari', 'tunggu', 'sekejap', 'cepat',
      'lambat', 'mahal', 'murah', 'tiket', 'bas', 'teksi', 'hotel',
    ];
    const enMarkers = [
      'the', 'this', 'that', 'is', 'are', 'was', 'you', 'your', 'where',
      'what', 'when', 'how', 'why', 'please', 'thank', 'thanks', 'want',
      'need', 'help', 'hello', 'my', 'gate', 'toilet', 'water', 'food',
      'airport', 'flight', 'excuse', 'sorry', 'can', 'could', 'would',
      'should', 'have', 'has', 'do', 'does', 'not', 'yes', 'okay', 'and',
      'but', 'with', 'for', 'from', 'here', 'there', 'go', 'come',
    ];

    final words = text.toLowerCase().split(RegExp(r'[^a-z]+'));
    var msScore = 0;
    var enScore = 0;
    for (final w in words) {
      if (w.isEmpty) continue;
      if (msMarkers.contains(w)) {
        msScore++;
      } else if (enMarkers.contains(w)) {
        enScore++;
      }
    }
    return [msScore, enScore];
  }

  /// Translates [text] from [fromLang] into [toLang].
  /// Falls back to the original text if the network request fails so the
  /// dialogue stream never blocks on connectivity.
  Future<String> translateText({
    required String text,
    required String fromLang,
    required String toLang,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return text;
    if (fromLang.toLowerCase() == toLang.toLowerCase()) return text;

    try {
      final response = await SupabaseClientHelper.client.functions
          .invoke(
            'translate-mobile-text',
            body: {
              'text': trimmed,
              'source': _libreLangCode(fromLang),
              'target': _libreLangCode(toLang),
            },
          )
          .timeout(const Duration(seconds: 10));
      final data = response.data;
      if (data is Map) {
        final translated = data['translatedText']?.toString().trim() ?? '';
        if (translated.isNotEmpty) return translated;
      }
    } catch (e) {
      debugPrint('Translation unavailable, returning original text: $e');
    }
    return text;
  }

  static String _libreLangCode(String lang) {
    switch (lang.toLowerCase()) {
      case 'zh':
      case 'cn':
        return 'zh';
      case 'ms':
      case 'my':
        return 'ms';
      default:
        return 'en';
    }
  }
}
