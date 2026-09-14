/// Scores a speech-recognition transcript for how likely it is a
/// public-address announcement rather than conversation or noise (FR-M2-08).
///
/// Signals combine into a composite confidence:
///  - keyword score: English and Bahasa Melayu public-address and transport
///    phrasing (delays, arrivals in N minutes, boarding, gates, stations...)
///  - place boost: a compact gazetteer of Malaysian transit places (LRT/MRT
///    stations, bus terminals, airports, cities and countries) nudges the
///    score up, but never validates an announcement on its own — a place name
///    alone also occurs in ordinary conversation.
///  - repetition boost: PA announcements are typically repeated twice, so a
///    similar transcript heard again within the repetition window raises
///    confidence.
///  - paging-tone context: when the sound detector heard a chime, bell or
///    alarm immediately before or after the speech, the keyword floor is
///    relaxed — PA systems play a tone around the spoken message.
class AnnouncementScoreResult {
  final double detectionScore;
  final double keywordScore;
  final double placeBoost;
  final double repetitionBoost;
  final double confidence;
  final bool isAnnouncement;
  final int keywordHits;
  final List<String> matchedKeywords;
  final String language;

  const AnnouncementScoreResult({
    required this.detectionScore,
    required this.keywordScore,
    required this.placeBoost,
    required this.repetitionBoost,
    required this.confidence,
    required this.isAnnouncement,
    required this.keywordHits,
    required this.matchedKeywords,
    required this.language,
  });
}

class AnnouncementKeywordScorer {
  const AnnouncementKeywordScorer();

  /// Unambiguous public-address phrasing. One hit already suggests an
  /// announcement; several make it near-certain.
  static const _strong = <String>[
    // English — airport / airline
    'attention please', 'may i have your attention', 'your attention please',
    'final call', 'last call', 'final boarding call', 'now boarding',
    'passengers are reminded', 'passenger announcement', 'gate change',
    'gate closure', 'flight is delayed', 'has been delayed', 'is delayed',
    'has been cancelled', 'is cancelled', 'flight is cancelled',
    'we apologize for', 'we apologise for', 'apologize for the inconvenience',
    'apologise for the inconvenience', 'thank you for your patience',
    'please proceed to', 'proceed to gate', 'proceed to the gate',
    'unattended luggage', 'unattended baggage', 'unattended item',
    'lost and found', 'lost property', 'baggage claim', 'carousel',
    'check in counter', 'check-in counter', 'boarding gate', 'gate number',
    'is now boarding', 'boarding will begin', 'departs from',
    'departure time', 'bound for', 'security check', 'security screening',
    'passport control', 'immigration', 'customs', 'bag drop',
    // English — rail / bus
    'the next train', 'the next bus', 'next train', 'next bus',
    'next service', 'train to', 'bus to', 'service to', 'trains to',
    'is approaching', 'now approaching', 'arriving in', 'arrive in',
    'is now arriving', 'is arriving', 'expected to arrive',
    'will arrive in', 'stand clear of the closing doors',
    'please stand clear of', 'mind the gap', 'please stand behind',
    'the yellow line', 'service disruption', 'disruption', 'not in service',
    'no service between', 'delays of up to', 'minor delays', 'severe delays',
    'scheduled maintenance', 'planned engineering', 'planned track',
    'this train terminates', 'terminates here', 'terminus',
    'is out of service', 'temporary timetable', 'replacement bus service',
    'lift out of service', 'escalator out of service',
    // English — generic PA
    'please note that', 'kindly note', 'this is an announcement',
    'please be informed', 'please be advised', 'for your safety',
    'attention passengers', 'ladies and gentlemen', 'passengers for flight',
    'should proceed to', 'boarding begins', 'we have now reached',
    'we have now reach', 'have reached the destination', 'enjoy the flight',
    'emergency exit', 'keep your belongings', 'do not leave your belongings',
    'please queue', 'queue here', 'please form a line', 'in a few minutes',
    'in approximately', 'remains closed', 'is now open',
    // Bahasa Melayu — airport / airline
    'perhatian', 'sila perhatikan', 'silakan perhatikan',
    'panggilan terakhir', 'panggilan akhir', 'kini menaiki', 'sedang menaiki',
    'penumpang diingatkan', 'penumpang dikehendaki', 'penerbangan',
    'penerbangan anda', 'telah ditunda', 'telah ditangguhkan',
    'ditangguhkan', 'telah dibatalkan', 'dibatalkan', 'akan berlepas',
    'bertolak', 'masa bertolak', 'gerbang penerbangan', 'no gerbang',
    'nombor gerbang', 'menuju ke', 'menuju', 'kaunter pendaftaran',
    'daftar masuk', 'pemeriksaan keselamatan', 'kawalan imigresen',
    'kastam', 'tuntutan bagasi', 'karusel', 'bagasi tidak dijaga',
    'barangan tidak dijaga', 'kita memohon maaf', 'memohon maaf',
    'terima kasih atas kesabaran', 'sila menuju ke',
    // Bahasa Melayu — rail / bus
    'tren seterusnya', 'bas seterusnya', 'perkhidmatan seterusnya',
    'tiba dalam', 'akan tiba', 'sedang tiba', 'sedang menghampiri',
    'akan tiba dalam', 'dijangka tiba', 'sila beri laluan',
    'jangan berdiri di depan pintu', 'berhati-hati apabila melangkah',
    'sila berdiri di belakang', 'garisan kuning', 'gangguan perkhidmatan',
    'penyelenggaraan', 'bukan dalam perkhidmatan', 'tiada perkhidmatan',
    'tren ini berakhir', 'berakhir di', 'destinasi terakhir',
    'bas pengganti', 'tangga bergerak rosak', 'lif rosak',
    // Bahasa Melayu — generic PA
    'sila ambil perhatian', 'makluman', 'pengumuman', 'dengan ini',
    'untuk keselamatan anda', 'pintu kecemasan', 'jangan tinggalkan barangan',
    'sila beratur', 'beratur di sini', 'dalam beberapa minit',
    'dalam masa', 'kira-kira', 'tutup sementara', 'dibuka semula',
    // English — hospital / mall / venue paging
    'please report to', 'would patient', 'would passenger',
    'would the owner of', 'will be closing', 'is now closing',
    'please collect', 'lost child', 'meeting will begin',
    'service resumes', 'please be seated',
    // Bahasa Melayu — hospital / mall / venue paging
    'sila hadir ke', 'sila ke kaunter', 'akan ditutup', 'sedang ditutup',
  ];

  /// Supporting transport vocabulary. One hit alone is weak; combined with
  /// other signals it strengthens the classification.
  static const _moderate = <String>[
    'gate',
    'boarding',
    'flight',
    'delay',
    'delayed',
    'cancelled',
    'cancellation',
    'departure',
    'departing',
    'arrive',
    'arriving',
    'minutes',
    'minute',
    'platform',
    'station',
    'terminal',
    'counter',
    'queue',
    'passengers',
    'disruption',
    'maintenance',
    'on time',
    'schedule',
    'timetable',
    'security',
    'baggage',
    'luggage',
    'train',
    'bus',
    'transit',
    'lane',
    'peron',
    'stesen',
    'tangguh',
    'batal',
    'berlepas',
    'tiba',
    'minit',
    'gerbang',
    'penerbangan',
    'kaunter',
    'beratur',
    'penumpang',
    'gangguan',
    'penyelenggaraan',
    'keselamatan',
    'bagasi',
    'tren',
    'keretapi',
    'bas',
    'hentian',
    'jadual',
    'tiket',
    'lapangan terbang',
    'terminal bas',
    'stesen bas',
    'hentian bas',
  ];

  /// Compact gazetteer of Malaysian transit places plus common destination
  /// cities and countries. Low weight: contextual only (see class doc).
  static const _places = <String>[
    // Klang Valley rail
    'kl sentral', 'klcc', 'bukit bintang', 'masjid jamek', 'pasar seni',
    'kuala lumpur', 'titiwangsa', 'sentul', 'sentul timur', 'ampang',
    'sri petaling', 'putra heights', 'kajang', 'kelana jaya', 'gombak',
    'wangsa maju', 'setiawangsa', 'jelatek', 'pandan jaya', 'maluri',
    'taman midah', 'cempaka', 'pandan indah', 'cochrane', 'taman connaught',
    'usj', 'subang jaya', 'shah alam', 'klang', 'putrajaya', 'cyberjaya',
    'puchong', 'kepong', 'selayang', 'bukit jalil', 'sungai buloh',
    'kwasa damansara', 'kota damansara', 'surian', 'mutiara damansara',
    'bandar utama', 'taman tun', 'ttdi', 'damansara', 'semantan',
    'pusat bandar', 'phileo damansara', 'pwtc', 'bandar tasik selatan',
    'salak selatan', 'seputeh', 'mid valley', 'abdullah hukum',
    'kerinchi', 'gleneagles', 'universiti', 'asia jaya', 'taman jaya',
    'kl gateway', 'kampung baru', 'dato keramat', 'damai', 'pudu',
    'chan sow lin', 'bandar tun razak', 'taman perdana', 'taman sri muda',
    // Airports
    'klia', 'klia2', 'kuala lumpur international airport', 'gateway@klia2',
    'subang airport', 'sultan abdul aziz shah airport', 'penang airport',
    'senai airport', 'kuching airport', 'kota kinabalu airport',
    'langkawi airport', 'changi', 'don mueang', 'suvarnabhumi',
    // Cities / states / countries
    'penang', 'pulau pinang', 'johor', 'johor bahru', 'jb sentral',
    'woodlands', 'singapore', 'ipoh', 'butterworth', 'alor setar',
    'kota bharu', 'kuala terengganu', 'kuantan', 'kuching', 'kota kinabalu',
    'sandakan', 'miri', 'langkawi', 'george town', 'melaka', 'malacca',
    'seremban', 'rawang', 'batu caves', 'sungai petani', 'taiping',
    'kuala selangor', 'sepang', 'bangkok', 'jakarta', 'london',
    'hong kong', 'beijing', 'shanghai', 'guangzhou', 'shenzhen', 'taipei',
    'seoul', 'incheon', 'tokyo', 'osaka', 'dubai', 'doha', 'istanbul',
    'sydney', 'melbourne', 'perth', 'manila', 'ho chi minh', 'hanoi',
    'phnom penh', 'yangon', 'colombo', 'chennai', 'mumbai', 'delhi',
    'surabaya', 'bali', 'denpasar', 'bandung', 'medan',
    // Bus terminals
    'tbs', 'terminal bersepadu selatan', 'hentian duta', 'puduraya',
    'terminal skypark', 'penang sentral', 'larkin sentral',
    // Airlines
    'malaysia airlines', 'airasia', 'air asia', 'batik air', 'malindo air',
    'lion air', 'singapore airlines', 'scoot', 'cathay pacific',
    'emirates', 'qatar airways', 'turkish airlines', 'china southern',
    'xiamen air', 'eva air', 'thai airways', 'vietnam airlines',
    'firefly', 'bangkok airways',
  ];

  static final List<(String, RegExp)> _strongMatchers = _buildMatchers(_strong);
  static final List<(String, RegExp)> _moderateMatchers = _buildMatchers(
    _moderate,
  );
  static final List<RegExp> _placeMatchers = _places
      .where((place) => place.isNotEmpty)
      .map(_wordMatcher)
      .toList(growable: false);

  static RegExp _wordMatcher(String phrase) =>
      RegExp('\\b${RegExp.escape(phrase)}\\b');

  static List<(String, RegExp)> _buildMatchers(List<String> phrases) => phrases
      .map((phrase) => (phrase, _wordMatcher(phrase)))
      .toList(growable: false);

  AnnouncementScoreResult score(
    String transcript,
    double detectionScore, {
    int repetitionCount = 1,
    bool pagingTone = false,
  }) {
    final normalized = transcript
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final strongHits = <String>[];
    var moderateHits = 0;
    var malayHits = 0;
    var englishHits = 0;

    for (final (phrase, matcher) in _strongMatchers) {
      if (matcher.hasMatch(normalized)) {
        strongHits.add(phrase);
        if (_isMalay(phrase)) {
          malayHits += 1;
        } else {
          englishHits += 1;
        }
      }
    }
    for (final (_, matcher) in _moderateMatchers) {
      if (matcher.hasMatch(normalized)) {
        moderateHits += 1;
        if (_isMalay(matcher.pattern)) {
          malayHits += 1;
        } else {
          englishHits += 1;
        }
      }
    }

    final matchedPlaces = _placeMatchers
        .where((matcher) => matcher.hasMatch(normalized))
        .length;

    // 2-3 strong hits already saturate the keyword score.
    final keywordScore = (strongHits.length * 1.0 + moderateHits * 0.4) / 2.5;
    final clampedKeywordScore = keywordScore.clamp(0.0, 1.0);
    final placeBoost = matchedPlaces > 0 ? 0.1 : 0.0;
    final repetitionBoost = repetitionCount >= 2 ? 0.2 : 0.0;
    final toneBoost = pagingTone ? 0.15 : 0.0;

    final composite =
        0.25 * detectionScore.clamp(0.0, 1.0) +
        0.55 * clampedKeywordScore +
        placeBoost +
        repetitionBoost +
        toneBoost;
    final confidence = composite.clamp(0.0, 1.0);

    // A paging tone (chime/bell/alarm) immediately around the speech is
    // strong PA-system evidence, so the keyword floor is relaxed.
    final isAnnouncement =
        (confidence >= 0.55 && clampedKeywordScore >= 0.30) ||
        (repetitionCount >= 2 &&
            clampedKeywordScore >= 0.20 &&
            confidence >= 0.40) ||
        (pagingTone && clampedKeywordScore >= 0.15 && confidence >= 0.45);

    final language = malayHits > englishHits ? 'ms' : 'en';

    return AnnouncementScoreResult(
      detectionScore: detectionScore,
      keywordScore: clampedKeywordScore,
      placeBoost: placeBoost,
      repetitionBoost: repetitionBoost,
      confidence: confidence,
      isAnnouncement: isAnnouncement,
      keywordHits: strongHits.length + moderateHits,
      matchedKeywords: strongHits,
      language: language,
    );
  }

  bool _isMalay(String phrase) {
    // Malay word list lives in the same tables; detect by a marker comment is
    // fragile, so use a keyword characteristic check on the phrase itself.
    return _malayMarkers.any(phrase.contains);
  }

  static const _malayMarkers = [
    'sila',
    'perhatian',
    'penerbangan',
    'tiba',
    'berlepas',
    'gerbang',
    'kaunter',
    'bagasi',
    'penumpang',
    'beratur',
    'tren',
    'bas',
    'bas seterusnya',
    'perkhidmatan',
    'gangguan',
    'penyelenggaraan',
    'keselamatan',
    'maaf',
    'tangguh',
    'batal',
    'minit',
    'stesen',
    'hentian',
    'jadual',
    'kastam',
    'imigresen',
    'kesabaran',
    'peron',
    'lif',
    'tangga',
    'makluman',
    'pengumuman',
    'kecemasan',
    'tiket',
    'lapangan',
    'menaiki',
    'menuju',
    'berakhir',
    'pengganti',
    'rosak',
    'dalam',
    'kira-kira',
    'dikehendaki',
    'dijaga',
    'berhati',
    'garisan',
    'beri',
    'lalu',
    'atur',
    'tutup',
    'dibuka',
    'dengan',
    'untuk',
    'dijangka',
    'destinasi',
    'terima',
    'wajib',
    'melangkah',
    'berdiri',
    'kuning',
  ];
}
