import 'package:flutter/services.dart';

/// Shared by typing/paste filtering and submission validation, including
/// non-Latin names and combining accents.
class TravellerName {
  static final characters = RegExp(r"[\p{L}\p{M} '\-’]", unicode: true);
  static final _valid = RegExp(r"^[\p{L}\p{M} '\-’]+$", unicode: true);
  static final _letter = RegExp(r'\p{L}', unicode: true);
  static TextInputFormatter get formatter =>
      FilteringTextInputFormatter.allow(characters);

  static String? validate(String value) {
    if (RegExp(r'\p{N}', unicode: true).hasMatch(value)) {
      return 'Name must not contain numbers.';
    }
    if (!_valid.hasMatch(value) || !_letter.hasMatch(value)) {
      return 'Name may contain only letters, spaces, hyphens and apostrophes.';
    }
    if (value.trim().length < 2 || value.trim().length > 80) {
      return 'Full name must be between 2 and 80 characters.';
    }
    return null;
  }
}
