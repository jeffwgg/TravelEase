/// A presentation-safe version of a speech-recognition result.
///
/// The original recogniser text is kept separately in [CapturedAnnouncement]
/// so an automatic rewrite never becomes the only record of what the device
/// heard.
class AnnouncementTextRefinement {
  final String title;
  final String transcript;
  final bool usedAi;

  const AnnouncementTextRefinement({
    required this.title,
    required this.transcript,
    required this.usedAi,
  });
}

/// Formats captured PA transcripts deterministically on the device. It never
/// asks travellers to provide a model file and never changes uncertain facts.
class AnnouncementTextRefiner {
  static final AnnouncementTextRefiner instance = AnnouncementTextRefiner._();

  AnnouncementTextRefiner._();

  /// Deterministic formatting for every capture, with no network or model.
  static AnnouncementTextRefinement formatLocally(String transcript) {
    final formatted = _sentenceCase(
      _applyAnnouncementTemplate(_cleanText(transcript)),
    );
    return AnnouncementTextRefinement(
      title: _titleFor(formatted),
      transcript: formatted,
      usedAi: false,
    );
  }

  static String _cleanText(String value) {
    var text = value
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\s+([,.;:!?])'), r'$1')
        .trim();

    // Common transit abbreviations are frequently spoken letter-by-letter.
    // These substitutions are deliberately narrow: they correct formatting,
    // not uncertain words or facts.
    const replacements = <String, String>{
      r'\bK\s*L\s*I\s*A\b': 'KLIA',
      r'\bK\s*L\s*Sentral\b': 'KL Sentral',
      r'\bM\s*R\s*T\b': 'MRT',
      r'\bL\s*R\s*T\b': 'LRT',
      r'\bE\s*T\s*A\b': 'ETA',
      r'\bfloght\b': 'flight',
      r'\bflite\b': 'flight',
    };
    replacements.forEach((pattern, replacement) {
      text = text.replaceAll(
        RegExp(pattern, caseSensitive: false),
        replacement,
      );
    });
    text = _normaliseFlightNumbers(text);
    text = _normaliseTransportFields(text);
    text = _normaliseMinutes(text);

    // These are exact, locally maintained aliases. They only standardise a
    // recognised place name; they do not guess an unknown destination.
    const placeAliases = <String, String>{
      r'\bKuala\s+Lumpur\s+Central\b': 'KL Sentral',
      r'\bK\s*L\s+Central\b': 'KL Sentral',
      r'\bKLIA\s+(?:two|2)\b': 'KLIA 2',
      r'\bAir\s+Asia\b': 'AirAsia',
      r'\bMalaysia\s+Airlines\b': 'Malaysia Airlines',
      r'\bMasjid\s+Jamek\b': 'Masjid Jamek',
      r'\bPasar\s+Seni\b': 'Pasar Seni',
      r'\bBukit\s+Bintang\b': 'Bukit Bintang',
      r'\bTitiwangsa\b': 'Titiwangsa',
      r'\bBandar\s+Tasik\s+Selatan\b': 'Bandar Tasik Selatan',
      r'\bSungai\s+Buloh\b': 'Sungai Buloh',
    };
    placeAliases.forEach((pattern, replacement) {
      text = text.replaceAll(
        RegExp(pattern, caseSensitive: false),
        replacement,
      );
    });
    return text;
  }

  /// Converts unambiguous, letter-by-letter airline codes plus spoken digits
  /// into the conventional flight-number form, for example “M H one two
  /// three” becomes “MH123”. The carrier must be in this small local list so
  /// normal words are never converted as though they were a flight number.
  static String _normaliseFlightNumbers(String text) {
    const numberWords = <String, String>{
      'zero': '0',
      'oh': '0',
      'one': '1',
      'two': '2',
      'three': '3',
      'four': '4',
      'five': '5',
      'six': '6',
      'seven': '7',
      'eight': '8',
      'nine': '9',
    };
    final matcher = RegExp(
      r'\b(m\s*h|a\s*k|d\s*7|o\s*d|f\s*y|s\s*q|t\s*r|c\s*x|q\s*z|t\s*g|v\s*n|q\s*r|e\s*k|t\s*k|c\s*z|m\s*f|b\s*r|f\s*d)\s+((?:(?:zero|oh|one|two|three|four|five|six|seven|eight|nine|\d)\s*){1,4})\b',
      caseSensitive: false,
    );
    return text.replaceAllMapped(matcher, (match) {
      final code = match[1]!.replaceAll(RegExp(r'\s+'), '').toUpperCase();
      final digits = match[2]!
          .trim()
          .split(RegExp(r'\s+'))
          .map((part) => numberWords[part.toLowerCase()] ?? part)
          .join();
      if (!RegExp(r'^\d{1,4}$').hasMatch(digits)) return match[0]!;
      // The matcher intentionally consumes inter-word whitespace in the
      // spoken number. Put a separator back when one preceded the next word.
      final trailingSpace = RegExp(r'\s$').hasMatch(match[0]!) ? ' ' : '';
      return '$code$digits$trailingSpace';
    });
  }

  /// Standardises only explicit numeric gate/platform references. This keeps
  /// field names clear without treating an arbitrary word as a location.
  static String _normaliseTransportFields(String text) {
    var normalized = text.replaceAllMapped(
      RegExp(
        r'\b(?:gate|gerbang)\s+(?:number|no\.?|nombor\s+)?([a-z]?\s*\d+[a-z]?)\b',
        caseSensitive: false,
      ),
      (match) =>
          'Gate ${match[1]!.replaceAll(RegExp(r'\s+'), '').toUpperCase()}',
    );
    normalized = normalized.replaceAllMapped(
      RegExp(
        r'\b(?:platform|peron)\s+(?:number|no\.?|nombor\s+)?(\d+[a-z]?)\b',
        caseSensitive: false,
      ),
      (match) => 'Platform ${match[1]!.toUpperCase()}',
    );
    return normalized;
  }

  /// Spoken time values are safe to normalise only in an explicit duration,
  /// such as “boarding begins in ten minutes”.
  static String _normaliseMinutes(String text) {
    const numberWords = <String, String>{
      'one': '1',
      'two': '2',
      'three': '3',
      'four': '4',
      'five': '5',
      'six': '6',
      'seven': '7',
      'eight': '8',
      'nine': '9',
      'ten': '10',
      'fifteen': '15',
      'twenty': '20',
      'thirty': '30',
    };
    return text.replaceAllMapped(
      RegExp(
        r'\b(in|within)\s+(one|two|three|four|five|six|seven|eight|nine|ten|fifteen|twenty|thirty)\s+minutes?\b',
        caseSensitive: false,
      ),
      (match) => '${match[1]} ${numberWords[match[2]!.toLowerCase()]} minutes',
    );
  }

  /// Reorders only complete, high-confidence announcement patterns. If a
  /// phrase is incomplete or unfamiliar it is returned unchanged, rather than
  /// risking invented times, gates, destinations, or flight numbers.
  static String _applyAnnouncementTemplate(String value) {
    final text = value.trim().replaceFirst(RegExp(r'[.!?…]+$'), '');

    // A looping PA recording can be captured across its boundary: the tail
    // (“boarding begins…”) arrives before its repeated opening. Reorder only
    // this complete, explicitly recognisable pattern. Missing gate or
    // destination details deliberately stay missing.
    final wrappedBoarding = RegExp(
      r'^boarding\s+begins\s+in\s+(\d+)\s+minutes?\s+(ladies\s+and\s+gentlemen\s+passengers\s+for\s+flight\s+.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (wrappedBoarding != null) {
      final passengerCall = wrappedBoarding[2]!.replaceFirst(
        RegExp(r'^ladies\s+and\s+gentlemen\s+', caseSensitive: false),
        'Ladies and gentlemen, ',
      );
      return '$passengerCall. Boarding begins in ${wrappedBoarding[1]} minutes.';
    }

    final boarding = RegExp(
      r'^(?:flight\s+)?([a-z]{2}\d{1,4})\s+(?:is\s+)?(?:now\s+)?boarding(?:\s+(?:(?:at|from)\s+)?(?:gate\s+)?([a-z]?\d+[a-z]?))?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (boarding != null) {
      final gate = boarding[2]?.toUpperCase();
      return 'Flight ${boarding[1]!.toUpperCase()} is now boarding${gate == null ? '' : ' at Gate $gate'}.';
    }

    final flightStatus = RegExp(
      r'^flight\s+([a-z]{2}\d{1,4})\s+(?:has\s+been|is)\s+(delayed|cancelled)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (flightStatus != null) {
      return 'Flight ${flightStatus[1]!.toUpperCase()} is ${flightStatus[2]!.toLowerCase()}.';
    }

    final gateChange = RegExp(
      r'^(?:the\s+)?gate\s+([a-z]?\d+[a-z]?)\s+(?:has\s+)?(?:been\s+)?changed(?:\s+to\s+(?:gate\s+)?([a-z]?\d+[a-z]?))?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (gateChange != null) {
      final oldGate = gateChange[1]!.toUpperCase();
      final newGate = gateChange[2]?.toUpperCase();
      return newGate == null
          ? 'Gate $oldGate has changed.'
          : 'Gate $oldGate has changed to Gate $newGate.';
    }

    final nextService = RegExp(
      r'^(?:the\s+)?next\s+(train|bus)\s+(?:to\s+(.+?)\s+)?(?:is\s+)?(arriving|approaching)(?:\s+at)?\s+(?:platform\s+)?([a-z]?\d+[a-z]?)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (nextService != null) {
      final destination = nextService[2]?.trim();
      final verb = nextService[3]!.toLowerCase();
      final platform = nextService[4]!.toUpperCase();
      return 'The next ${nextService[1]!.toLowerCase()}${destination == null ? '' : ' to $destination'} is $verb at Platform $platform.';
    }

    final proceedToGate = RegExp(
      r'^(?:please\s+)?proceed\s+to\s+(?:the\s+)?gate\s+([a-z]?\d+[a-z]?)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (proceedToGate != null) {
      return 'Please proceed to Gate ${proceedToGate[1]!.toUpperCase()}.';
    }

    return value;
  }

  static String _sentenceCase(String value) {
    if (value.isEmpty) return value;
    final buffer = StringBuffer();
    var capitaliseNextLetter = true;
    for (final codePoint in value.runes) {
      final character = String.fromCharCode(codePoint);
      if (capitaliseNextLetter && RegExp(r'[A-Za-z]').hasMatch(character)) {
        buffer.write(character.toUpperCase());
        capitaliseNextLetter = false;
      } else {
        buffer.write(character);
        if (RegExp(r'[A-Za-z]').hasMatch(character)) {
          capitaliseNextLetter = false;
        }
      }
      if (character == '.' || character == '!' || character == '?') {
        capitaliseNextLetter = true;
      }
    }
    final sentence = buffer.toString();
    return RegExp(r'[.!?…]$').hasMatch(sentence) ? sentence : '$sentence.';
  }

  static String _titleFor(String transcript) {
    final normalized = transcript.toLowerCase();
    if (RegExp(r'\b(gate|gerbang).{0,20}\b(change|changed|tukar)\b')
        .hasMatch(normalized)) {
      return 'Gate change';
    }
    if (RegExp(
      r'\b(final|last|terakhir)\s+(?:boarding\s+)?(call|panggilan|menaiki)\b',
    ).hasMatch(normalized)) {
      return 'Final boarding call';
    }
    if (RegExp(r'\b(delay|delayed|ditunda|ditangguhkan)\b')
        .hasMatch(normalized)) {
      return 'Service delay';
    }
    if (RegExp(r'\b(cancelled|cancellation|dibatalkan)\b')
        .hasMatch(normalized)) {
      return 'Service cancellation';
    }
    if (RegExp(
      r'\b(train|tren|bus|bas).{0,30}\b(arriv\w*|tiba|approach\w*|menghampiri)\b',
    ).hasMatch(normalized)) {
      return 'Arrival announcement';
    }
    if (RegExp(
      r'\b(now boarding|boarding now|boarding begins|sedang menaiki|kini menaiki)\b',
    ).hasMatch(normalized)) {
      return 'Boarding update';
    }
    if (RegExp(r'\b(safety|emergency|keselamatan|kecemasan)\b')
        .hasMatch(normalized)) {
      return 'Safety announcement';
    }
    if (RegExp(r'\b(gate|gerbang)\b').hasMatch(normalized)) {
      return 'Gate update';
    }
    if (RegExp(r'\b(flight|penerbangan)\b').hasMatch(normalized)) {
      return 'Flight update';
    }
    if (RegExp(r'\b(train|tren|bus|bas|station|stesen|platform|peron)\b')
        .hasMatch(normalized)) {
      return 'Transport service update';
    }
    if (RegExp(r'\b(attention|announcement|perhatian|pengumuman)\b')
        .hasMatch(normalized)) {
      return 'Public announcement';
    }
    // A raw recognition sentence is not a useful heading. Use a stable,
    // readable category when the device cannot establish a more specific one.
    return 'Spoken announcement';
  }
}
