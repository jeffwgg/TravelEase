import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/entities/sign_language_entity.dart';

/// A resolved playable clip for a single gloss word.
class SignWordClip {
  final String word;
  final String source;
  bool get isNetwork => source.startsWith('http://') || source.startsWith('https://');

  const SignWordClip({required this.word, required this.source});
}

/// Resolves per-word sign video files following the naming convention:
///
///   assets/signs/`<lang>`/`<slug>`.mp4          (front view)
///   assets/signs/`<lang>`/`<slug>`_side.mp4     (optional side view)
///   assets/signs/`<lang>`/_fallback.mp4         (optional per-language fallback)
///
/// where `<slug>` is the lowercase gloss token keeping only a-z0-9,
/// any other character run collapsed into a single '_', and trimmed
/// (e.g. 'CHECK-IN' -> 'check_in', 'MANA ?' -> 'mana').
class SignWordVideoLibrary {
  SignWordVideoLibrary._();

  static const int fps = 30;
  static Set<String>? _cachedAssets;

  /// Normalize a gloss token into a file slug.
  static String slugify(String token) {
    final buffer = StringBuffer();
    var lastWasSeparator = false;
    for (final code in token.toLowerCase().runes) {
      final isAlnum = (code >= 0x61 && code <= 0x7A) || (code >= 0x30 && code <= 0x39);
      if (isAlnum) {
        buffer.writeCharCode(code);
        lastWasSeparator = false;
      } else if (!lastWasSeparator && buffer.isNotEmpty) {
        buffer.write('_');
        lastWasSeparator = true;
      }
    }
    var slug = buffer.toString();
    if (slug.endsWith('_')) slug = slug.substring(0, slug.length - 1);
    return slug;
  }

  /// Split a gloss string into word tokens (punctuation-only tokens removed).
  static List<String> parseGlossWords(String gloss) {
    return gloss
        .split(RegExp(r'\s+'))
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty && slugify(w).isNotEmpty)
        .toList();
  }

  static Future<Set<String>> _availableAssets() async {
    if (_cachedAssets != null) return _cachedAssets!;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      _cachedAssets = manifest.listAssets().toSet();
    } catch (_) {
      _cachedAssets = <String>{};
    }
    return _cachedAssets!;
  }

  /// Resolve an ordered playlist of clips for the given gloss words.
  /// Greedy multi-word matching: consecutive gloss tokens are joined so
  /// 'THANK YOU' can resolve to thank_you.mp4 when present (up to 3 tokens).
  /// Falls back to `<lang>/_fallback.mp4` when a word clip is missing.
  /// Returns an empty list when no assets exist at all for the language.
  static Future<List<SignWordClip>> resolveClipSources({
    required List<String> words,
    required SignLanguageType language,
    String perspective = 'front',
  }) async {
    final assets = await _availableAssets();
    final langDir = 'assets/signs/${language.code.toLowerCase()}';
    final wantSide = perspective.toLowerCase() == 'side';

    String? pick(String slug) {
      if (slug.isEmpty) return null;
      if (wantSide) {
        final sidePath = '$langDir/${slug}_side.mp4';
        if (assets.contains(sidePath)) return sidePath;
      }
      final frontPath = '$langDir/$slug.mp4';
      return assets.contains(frontPath) ? frontPath : null;
    }

    String? fallbackSource;
    final fallbackPath = '$langDir/_fallback.mp4';
    if (assets.contains(fallbackPath)) fallbackSource = fallbackPath;

    final clips = <SignWordClip>[];
    var i = 0;
    while (i < words.length) {
      final baseSlug = slugify(words[i]);
      if (baseSlug.isEmpty) {
        i++;
        continue;
      }

      // Greedy longest match first: 'THANK YOU MUCH' -> thank_you_much.mp4?
      String? source;
      var consumed = 1;
      for (final n in const [3, 2]) {
        if (i + n > words.length) continue;
        final joinedSlug = slugify(words.sublist(i, i + n).join('-'));
        final hit = pick(joinedSlug);
        if (hit != null) {
          source = hit;
          consumed = n;
          break;
        }
      }

      source ??= pick(baseSlug) ?? fallbackSource;
      if (source == null) {
        debugPrint('[SignVideo] MISSING: $langDir/$baseSlug.mp4 ("${words[i]}")');
        i++;
        continue;
      }

      final display = words.sublist(i, i + consumed).join(' ').toUpperCase();
      debugPrint('[SignVideo] Resolved "$display" -> $source');
      clips.add(SignWordClip(word: display, source: source));
      i += consumed;
    }
    if (clips.isEmpty) {
      debugPrint('[SignVideo] No clips resolved for lang=${language.code}. '
          'Bundled sign assets found: ${assets.where((a) => a.startsWith("assets/signs/")).toList()}');
    }
    return clips;
  }
}
