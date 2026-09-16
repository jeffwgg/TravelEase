import 'package:flutter/foundation.dart';

import '../../core/supabase_client.dart';
import '../entities/sign_language_entity.dart';
import '../entities/sign_phrase_entity.dart';
import '../entities/favorite_phrase_entity.dart';

/// Repository for Module 4: Sign-Language Reference Engine Module (FR-M4-01 to FR-M4-19)
class SignReferenceRepository {
  final _client = SupabaseClientHelper.client;

  // Local fallback mock database for instant offline and rich sample experience
  static final List<SignPhrase> _inMemoryPhrases = [
    SignPhrase(
      id: 'a1111111-1111-1111-1111-111111111111',
      categoryId: 'airport',
      phraseEn: 'Where is the gate?',
      phraseMs: 'Di mana pintu masuk / perlepasan?',
      phraseZh: '登机口在哪里？',
      glossAsl: 'GATE WHERE ?',
      glossBim: 'PINTU MANA ?',
      glossCsl: '登机口 在哪 ?',
      scenario: 'Airport Departure / Boarding Area',
      stepInstructions: const [
        SignMovementStep(step: 1, title: 'Raise Open Palms', description: 'Raise both hands with open palms facing upward at chest level.'),
        SignMovementStep(step: 2, title: 'Move Hands Outward', description: 'Move both hands gently apart in an inquisitive questioning motion.'),
        SignMovementStep(step: 3, title: 'Point & Facial Expression', description: 'Point forward with dominant index finger while raising eyebrows.'),
      ],
      // Video playback is resolved per gloss word from assets/signs/<lang>/<word>.mp4
    ),
    SignPhrase(
      id: 'a2222222-2222-2222-2222-222222222222',
      categoryId: 'airport',
      phraseEn: 'I need to check in',
      phraseMs: 'Saya perlu daftar masuk',
      phraseZh: '我需要办理值机',
      glossAsl: 'I NEED CHECK-IN',
      glossBim: 'SAYA PERLU DAFTAR MASUK',
      glossCsl: '我 需要 办理 值机',
      scenario: 'Airport Counter / Terminal Entrance',
      stepInstructions: const [
        SignMovementStep(step: 1, title: 'Indicate Self', description: 'Tap chest with index finger to indicate yourself.'),
        SignMovementStep(step: 2, title: 'Sign Need / Require', description: 'Form a bent index finger and tap downward twice firmly.'),
        SignMovementStep(step: 3, title: 'Sign Pass Registration', description: 'Slide flat hand into open palm like presenting a boarding pass.'),
      ],
    ),
    SignPhrase(
      id: 'a3333333-3333-3333-3333-333333333333',
      categoryId: 'airport',
      phraseEn: 'My flight is delayed',
      phraseMs: 'Penerbangan saya tertangguh',
      phraseZh: '我的航班延误了',
      glossAsl: 'MY FLIGHT DELAY',
      glossBim: 'PENERBANGAN SAYA TANGGUH',
      glossCsl: '我 航班 延误',
      scenario: 'Flight Information Display',
      stepInstructions: const [
        SignMovementStep(step: 1, title: 'Sign Airplane', description: 'Extend thumb, index, and pinky (ILY shape) moving forward.'),
        SignMovementStep(step: 2, title: 'Sign Delay', description: 'Hold both hands in F-shape and move dominant hand forward slowly.'),
      ],
    ),
    SignPhrase(
      id: 'a4444444-4444-4444-4444-444444444444',
      categoryId: 'hotel',
      phraseEn: 'I have a reservation',
      phraseMs: 'Saya ada tempahan bilik',
      phraseZh: '我有房间预订',
      glossAsl: 'I HAVE ROOM RESERVATION',
      glossBim: 'SAYA ADA TEMPAH BILIK',
      glossCsl: '我 有 预订 房间',
      scenario: 'Hotel Reception Desk',
    ),
    SignPhrase(
      id: 'a5555555-5555-5555-5555-555555555555',
      categoryId: 'restaurant',
      phraseEn: 'Can I get the menu?',
      phraseMs: 'Boleh saya dapatkan menu?',
      phraseZh: '可以给我菜单吗？',
      glossAsl: 'CAN I SEE MENU ?',
      glossBim: 'BOLEH SAYA LIHAT MENU ?',
      glossCsl: '可以 给我 菜单 吗 ?',
      scenario: 'Dining Counter',
    ),
    SignPhrase(
      id: 'a6666666-6666-6666-6666-666666666666',
      categoryId: 'emergency',
      phraseEn: 'I need help / SOS',
      phraseMs: 'Saya perlukan bantuan kecemasan',
      phraseZh: '我需要紧急帮助',
      glossAsl: 'I NEED HELP SOS',
      glossBim: 'SAYA PERLU BANTUAN KECEMASAN',
      glossCsl: '我 需要 紧急 帮助',
      scenario: 'Emergency Incident / First Aid',
    ),
    SignPhrase(
      id: 'a7777777-7777-7777-7777-777777777777',
      categoryId: 'general',
      phraseEn: 'Thank you very much',
      phraseMs: 'Terima kasih banyak',
      phraseZh: '非常感谢',
      glossAsl: 'THANK-YOU MUCH',
      glossBim: 'TERIMA KASIH BANYAK',
      glossCsl: '非常 谢谢 你',
      scenario: 'General Conversation',
    ),
    SignPhrase(
      id: 'a8888888-8888-8888-8888-888888888888',
      categoryId: 'general',
      phraseEn: 'Hello, nice to meet you',
      phraseMs: 'Halo, selamat berkenalan',
      phraseZh: '你好，很高兴认识你',
      glossAsl: 'HELLO NICE-TO-MEET-YOU',
      glossBim: 'HALO GEMBIRA JUMPA AWAK',
      glossCsl: '你好 很高兴 认识 你',
      scenario: 'General Greeting',
    ),
    SignPhrase(
      id: 'a9999999-9999-9999-9999-999999999999',
      categoryId: 'transit',
      phraseEn: 'Which bus to the city center?',
      phraseMs: 'Bas mana pergi ke pusat bandar?',
      phraseZh: '哪趟巴士去市中心？',
      glossAsl: 'WHICH BUS GO CITY ?',
      glossBim: 'BAS MANA PUSAT BANDAR ?',
      glossCsl: '哪个 巴士 去 市中心 ?',
      scenario: 'Bus Terminal',
    ),
    SignPhrase(
      id: 'baaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      categoryId: 'medical',
      phraseEn: 'I feel sick and need a doctor',
      phraseMs: 'Saya rasa tidak sihat, perlu doktor',
      phraseZh: '我感觉不舒服，需要医生',
      glossAsl: 'I SICK NEED DOCTOR',
      glossBim: 'SAYA SAKIT PERLU DOKTOR',
      glossCsl: '我 生病 需要 医生',
      scenario: 'Clinic & Pharmacy',
    ),
  ];

  // Favorites: per-user offline mirror. The demo bucket keeps the seeded
  // sample list for signed-out guests; signed-in accounts get their own
  // bucket backed by user_favorite_phrases (never shared with the demo).
  static final Map<String, List<FavoritePhrase>> _favoritesByUser = {};

  /// Supabase id of the signed-in account, or the demo key for guests.
  String get currentUserId => _client.auth.currentUser?.id ?? 'demo_user';

  /// Email of the signed-in account (null for guests).
  String? get signedInEmail => _client.auth.currentUser?.email;

  bool get isSignedIn => _client.auth.currentUser != null;

  static final RegExp _uuidPattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
  static bool _isUuid(String value) => _uuidPattern.hasMatch(value);

  List<FavoritePhrase> _favoritesBucket(String userId) {
    return _favoritesByUser.putIfAbsent(userId, () {
      if (userId != 'demo_user') return <FavoritePhrase>[];
      return [
        FavoritePhrase(
          id: 'fav_1',
          userId: userId,
          phraseId: _inMemoryPhrases[0].id,
          orderIndex: 0,
          createdAt: DateTime.now(),
          phrase: _inMemoryPhrases[0],
        ),
        FavoritePhrase(
          id: 'fav_2',
          userId: userId,
          phraseId: _inMemoryPhrases[1].id,
          orderIndex: 1,
          createdAt: DateTime.now(),
          phrase: _inMemoryPhrases[1],
        ),
        FavoritePhrase(
          id: 'fav_3',
          userId: userId,
          phraseId: _inMemoryPhrases[5].id,
          orderIndex: 2,
          createdAt: DateTime.now(),
          phrase: _inMemoryPhrases[5],
        ),
        FavoritePhrase(
          id: 'fav_4',
          userId: userId,
          phraseId: _inMemoryPhrases[6].id,
          orderIndex: 3,
          createdAt: DateTime.now(),
          phrase: _inMemoryPhrases[6],
        ),
      ];
    });
  }

  // --------------------------------------------------------------------------
  // 1. Browse & Search Sign Dictionary (FR-M4-01, FR-M4-04, FR-M4-13, FR-M4-14)
  // --------------------------------------------------------------------------
  Future<List<SignPhrase>> searchSignDictionary({
    String? query,
    String? categoryId,
    SignLanguageType signLanguage = SignLanguageType.bim,
  }) async {
    try {
      var dbQuery = _client
          .from('sign_dictionary_phrases')
          .select('*, sign_media_assets(*)');

      if (categoryId != null && categoryId.isNotEmpty && categoryId.toLowerCase() != 'all') {
        dbQuery = dbQuery.eq('category_id', categoryId.toLowerCase());
      }

      final response = await dbQuery.order('created_at', ascending: true);
      List<SignPhrase> results = (response as List).map((p) => SignPhrase.fromJson(p)).toList();

      if (query != null && query.trim().isNotEmpty) {
        final q = query.trim().toLowerCase();
        results = results.where((p) {
          return p.phraseEn.toLowerCase().contains(q) ||
              p.phraseMs.toLowerCase().contains(q) ||
              p.phraseZh.toLowerCase().contains(q) ||
              (p.glossAsl?.toLowerCase().contains(q) ?? false) ||
              (p.glossBim?.toLowerCase().contains(q) ?? false) ||
              (p.glossCsl?.toLowerCase().contains(q) ?? false);
        }).toList();
      }

      if (results.isNotEmpty) return results;
    } catch (e) {
      // Fall through to memory
    }

    // Local in-memory filtering fallback
    var filtered = List<SignPhrase>.from(_inMemoryPhrases);
    if (categoryId != null && categoryId.isNotEmpty && categoryId.toLowerCase() != 'all') {
      filtered = filtered.where((p) => p.categoryId.toLowerCase() == categoryId.toLowerCase()).toList();
    }
    if (query != null && query.trim().isNotEmpty) {
      final q = query.trim().toLowerCase();
      filtered = filtered.where((p) {
        return p.phraseEn.toLowerCase().contains(q) ||
            p.phraseMs.toLowerCase().contains(q) ||
            p.phraseZh.toLowerCase().contains(q) ||
            (p.glossAsl?.toLowerCase().contains(q) ?? false) ||
            (p.glossBim?.toLowerCase().contains(q) ?? false) ||
            (p.glossCsl?.toLowerCase().contains(q) ?? false);
      }).toList();
    }
    return filtered;
  }

  // FR-M4-02 & FR-M4-03: Get Detailed Sign Phrase with gloss notations & movement steps
  Future<SignPhrase?> getSignPhraseDetails(String phraseId) async {
    try {
      final response = await _client
          .from('sign_dictionary_phrases')
          .select('*, sign_media_assets(*)')
          .eq('id', phraseId)
          .single();
      return SignPhrase.fromJson(response);
    } catch (e) {
      try {
        return _inMemoryPhrases.firstWhere((p) => p.id == phraseId);
      } catch (_) {
        return _inMemoryPhrases.first;
      }
    }
  }

  // --------------------------------------------------------------------------
  // 2. Favorites List & Bookmarks (FR-M4-17, FR-M4-18, FR-M4-19)
  //    Scoped to the signed-in Supabase account (user_id = auth uuid);
  //    guests keep the local demo bucket. An empty list for a signed-in
  //    user is their real state — it never falls back to dummy rows.
  // --------------------------------------------------------------------------
  Future<List<FavoritePhrase>> getFavoritePhrases(String userId) async {
    if (_isUuid(userId)) {
      try {
        final response = await _client
            .from('user_favorite_phrases')
            .select('*, sign_dictionary_phrases(*, sign_media_assets(*))')
            .eq('user_id', userId)
            .order('order_index', ascending: true);
        final list =
            (response as List).map((f) => FavoritePhrase.fromJson(f)).toList();
        _favoritesByUser[userId] = list; // mirror for offline reads
        return list;
      } catch (e) {
        debugPrint(
            '[SignReferenceRepository] favorites fetch failed for $userId: $e');
      }
    }
    return List.of(_favoritesBucket(userId));
  }

  Future<bool> addFavoritePhrase(String userId, String phraseId) async {
    final bucket = _favoritesBucket(userId);
    if (bucket.any((f) => f.phraseId == phraseId)) return true;

    var persisted = !_isUuid(userId);
    if (_isUuid(userId)) {
      try {
        await _client.from('user_favorite_phrases').upsert({
          'user_id': userId,
          'phrase_id': phraseId,
          'order_index': bucket.length,
        }, onConflict: 'user_id,phrase_id');
        persisted = true;
      } catch (e) {
        debugPrint(
            '[SignReferenceRepository] favorite add failed for $userId: $e');
        // Keep the optimistic local copy so the UI stays consistent
        // offline; the next successful load re-syncs from the server.
      }
    }
    final idx = _inMemoryPhrases.indexWhere((p) => p.id == phraseId);
    bucket.add(
      FavoritePhrase(
        id: persisted
            ? 'fav_${DateTime.now().millisecondsSinceEpoch}'
            : 'fav_local_${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        phraseId: phraseId,
        orderIndex: bucket.length,
        createdAt: DateTime.now(),
        phrase: idx >= 0 ? _inMemoryPhrases[idx] : null,
      ),
    );
    return true;
  }

  Future<bool> removeFavoritePhrase(String userId, String phraseId) async {
    if (_isUuid(userId)) {
      try {
        await _client
            .from('user_favorite_phrases')
            .delete()
            .eq('user_id', userId)
            .eq('phrase_id', phraseId);
      } catch (e) {
        debugPrint(
            '[SignReferenceRepository] favorite remove failed for $userId: $e');
      }
    }
    _favoritesBucket(userId)
        .removeWhere((f) => f.userId == userId && f.phraseId == phraseId);
    return true;
  }

  Future<bool> isFavorite(String userId, String phraseId) async {
    return _favoritesBucket(userId)
        .any((f) => f.userId == userId && f.phraseId == phraseId);
  }

  Future<void> reorderFavorites(String userId, int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final bucket = _favoritesBucket(userId);
    if (oldIndex < 0 ||
        oldIndex >= bucket.length ||
        newIndex < 0 ||
        newIndex >= bucket.length) {
      return;
    }
    bucket.insert(newIndex, bucket.removeAt(oldIndex));

    if (!_isUuid(userId)) return;
    try {
      // Persist the new position of each row whose order actually moved.
      for (var i = 0; i < bucket.length; i++) {
        if (bucket[i].orderIndex != i) {
          await _client
              .from('user_favorite_phrases')
              .update({'order_index': i})
              .eq('id', bucket[i].id);
        }
      }
    } catch (e) {
      debugPrint(
          '[SignReferenceRepository] favorite reorder failed for $userId: $e');
    }
  }

  // --------------------------------------------------------------------------
  // 4. (Removed) Moderation feedback — the Report button was retired from
  // the media viewer in favour of the favorites star; no callers remain.
  // --------------------------------------------------------------------------
}
