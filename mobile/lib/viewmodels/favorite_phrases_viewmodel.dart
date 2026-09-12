import 'package:flutter/foundation.dart';
import '../models/entities/favorite_phrase_entity.dart';
import '../models/repositories/sign_reference_repository.dart';

/// ViewModel for Bookmarked Favorite Phrases (FR-M4-17 to FR-M4-19).
///
/// Scoped to the signed-in Supabase account ([SignReferenceRepository
/// .currentUserId]); signed-out users keep the local demo bucket so the
/// offline experience stays functional, and [accountLabel] tells the UI
/// whose favorites are on screen.
class FavoritePhrasesViewModel extends ChangeNotifier {
  final SignReferenceRepository _repository;

  FavoritePhrasesViewModel({
    SignReferenceRepository? repository,
  }) : _repository = repository ?? SignReferenceRepository() {
    loadFavorites();
  }

  List<FavoritePhrase> _favorites = [];
  bool _isLoading = true;
  String? _statusMessage;

  List<FavoritePhrase> get favorites => List.unmodifiable(_favorites);
  bool get isLoading => _isLoading;
  String? get statusMessage => _statusMessage;

  /// True when the list shown belongs to a real Supabase account.
  bool get isSignedIn => _repository.isSignedIn;

  /// "email@…" for signed-in users, "Demo account" otherwise.
  String get accountLabel =>
      _repository.signedInEmail ?? 'Demo account (not signed in)';

  String get _userId => _repository.currentUserId;

  Future<void> loadFavorites() async {
    _isLoading = true;
    notifyListeners();

    try {
      final list = await _repository.getFavoritePhrases(_userId);
      _favorites = list;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _favorites = const [];
      _statusMessage = 'Could not load favorites.';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> removeFavorite(FavoritePhrase fav) async {
    _favorites.removeWhere((f) => f.id == fav.id);
    notifyListeners();

    await _repository.removeFavoritePhrase(_userId, fav.phraseId);
  }

  Future<void> restoreFavorite(FavoritePhrase fav) async {
    await _repository.addFavoritePhrase(_userId, fav.phraseId);
    loadFavorites();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _favorites.removeAt(oldIndex);
    _favorites.insert(newIndex, item);
    notifyListeners();

    await _repository.reorderFavorites(_userId, oldIndex, newIndex);
  }
}
