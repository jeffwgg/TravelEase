/// Shared word→sentence assembly for ASL and BIM (port of
/// `training_resources/bim/slr/scripts/templates.py`).
///
/// Recognition produces loose gloss words; both dialects feed the SAME
/// engine: unordered keyword-set matching (biggest subset first, up to 3
/// words), yielding a phrase with all three output languages ready.
/// BIM glosses are Malay and the table mirrors the Python templates 1:1;
/// ASL glosses are English GISLR words with an equivalent table.
/// Unmatched word sets fall back to the plain word list (matched=false),
/// which the viewmodel then machine-translates like before.
class AssembledPhrase {
  const AssembledPhrase({
    required this.words,
    required this.matched,
    required this.sourceLang,
    required this.en,
    required this.ms,
    required this.zh,
  });

  /// Glosses recognized so far, in signing order.
  final List<String> words;
  final bool matched;

  /// Language the raw word list is in: 'ms' for BIM glosses, 'en' for ASL.
  final String sourceLang;
  final String en;
  final String ms;
  final String zh;

  String forLang(String lang) => switch (lang) {
        'en' => en,
        'zh' => zh,
        _ => ms,
      };

  static const empty = AssembledPhrase(
    words: [],
    matched: false,
    sourceLang: 'ms',
    en: '',
    ms: '',
    zh: '',
  );
}

/// One template: an unordered key set -> sentence in all languages.
class _Template {
  const _Template(this.keys, this.en, this.ms, this.zh);
  final Set<String> keys;
  final String en;
  final String ms;
  final String zh;
}

class TravelPhraseAssembler {
  static const int maxTemplateWords = 3;

  // --- BIM (Malay glosses; 1:1 with training_resources/bim/slr/scripts/templates.py + the
  //     MALAY_TO_ENGLISH map from bim_api.py) ------------------------------
  static const _bimTemplates = [
    _Template({'tandas', 'mana'}, 'Where is the toilet?', 'Di mana tandas?', '廁所在哪裏?'),
    _Template({'hospital', 'mana'}, 'Where is the hospital?', 'Di mana hospital?', '醫院在哪裏?'),
    _Template({'polis', 'mana'}, 'Where is the police station?', 'Di mana balai polis?', '警察局在哪裏?'),
    _Template({'kedai', 'mana'}, 'Where is the shop?', 'Di mana kedai?', '商店在哪裏?'),
    _Template({'kafetaria', 'mana'}, 'Where is the restaurant?', 'Di mana kafetaria?', '餐廳在哪裏?'),
    _Template({'bas', 'mana'}, 'Where is the bus station?', 'Di mana stesen bas?', '巴士站在哪裏?'),
    _Template({'keretapi', 'mana'}, 'Where is the train station?', 'Di mana stesen keretapi?', '火車站在哪裏?'),
    _Template({'teksi', 'mana'}, 'Where can I take a taxi?', 'Di mana boleh naik teksi?', '哪裏可以搭計程車?'),
    _Template({'pergi', 'kiri'}, 'Please go left.', 'Sila pergi ke kiri.', '請往左邊走。'),
    _Template({'pergi', 'kanan'}, 'Please go right.', 'Sila pergi ke kanan.', '請往右邊走。'),
    _Template({'pergi', 'terus'}, 'Please go straight.', 'Terus jalan sahaja.', '請一直往前走。'),
    _Template({'pergi', 'pusing', 'kiri'}, 'Turn left ahead.', 'Pusing ke kiri di hadapan.', '前面左轉。'),
    _Template({'pergi', 'pusing', 'kanan'}, 'Turn right ahead.', 'Pusing ke kanan di hadapan.', '前面右轉。'),
    _Template({'pergi', 'arah'}, 'Go in this direction.', 'Jalan ikut arah ini.', '往這個方向走。'),
    _Template({'berapa', 'duit'}, 'How much does it cost?', 'Berapa harganya?', '請問多少錢?'),
    _Template({'harga'}, 'How much does it cost?', 'Berapa harganya?', '請問多少錢?'),
    _Template({'harga', 'ini'}, 'How much is this one?', 'Berapa harga yang ini?', '請問這個多少錢?'),
    _Template({'ini', 'berapa'}, 'How much is this one?', 'Berapa harga yang ini?', '請問這個多少錢?'),
    _Template({'beli', 'ini'}, 'I want to buy this one.', 'Saya nak beli yang ini.', '我想買這個。'),
    _Template({'mahal'}, 'Too expensive.', 'Terlalu mahal.', '太貴了。'),
    _Template({'beli', 'tiket'}, 'I want to buy a ticket.', 'Saya nak beli tiket.', '我想買票。'),
    _Template({'tolong'}, 'Help! I need assistance.', 'Tolong! Saya perlukan bantuan.', '幫助!我需要幫忙。'),
    _Template({'minum', 'air'}, 'May I have some water?', 'Boleh saya dapatkan air?', '可以給我一杯水嗎?'),
    _Template({'makan'}, 'I am hungry and want to eat.', 'Saya lapar, nak makan.', '我餓了,想吃東西。'),
    _Template({'makan', 'mana'}, 'Where can I eat?', 'Di mana boleh makan?', '哪裏可以吃飯?'),
    _Template({'jangan'}, 'No, thank you.', 'Tidak, terima kasih.', '不用了,謝謝。'),
    _Template({'boleh'}, 'Is that possible?', 'Boleh tak?', '可以嗎?'),
    _Template({'kesakitan'}, 'I am in pain.', 'Saya sakit.', '我痛/不舒服。'),
    _Template({'hilang_habis'}, 'My belongings are missing.', 'Barang saya hilang.', '我的東西不見了。'),
    _Template({'telefon'}, 'May I borrow a phone?', 'Boleh pinjam telefon?', '可以借電話嗎?'),
    _Template({'terima_kasih'}, 'Thank you!', 'Terima kasih!', '謝謝!'),
    _Template({'apa_khabar'}, 'How are you?', 'Apa khabar?', '你好嗎?'),
    _Template({'selamat_pagi'}, 'Good morning!', 'Selamat pagi!', '早安!'),
    _Template({'nama', 'saya'}, 'My name is...', 'Nama saya...', '我的名字是...'),
    _Template({'bila'}, 'When?', 'Bila?', '什麼時候?'),
    _Template({'apa'}, 'What is this?', 'Apa ini?', '這是什麼?'),
    // Extras for the presenter's locked BIM set.
    _Template({'saya', 'tandas'}, 'I need the toilet.', 'Saya perlu tandas.', '我需要上廁所。'),
    _Template({'saya', 'tolong'}, 'I need help.', 'Saya perlukan tolong.', '我需要幫助。'),
    _Template({'saya', 'hospital'}, 'I need a hospital.', 'Saya perlu hospital.', '我需要去醫院。'),
    _Template({'saya', 'bas'}, 'I need the bus.', 'Saya perlu bas.', '我需要坐巴士。'),
  ];

  // --- ASL (English GISLR words; same matching semantics) -----------------
  static const _aslTemplates = [
    _Template({'where', 'water'}, 'Where is the water?', 'Di mana air?', '水在哪里？'),
    _Template({'where', 'airplane'}, 'Where is the airplane?', 'Di mana kapal terbang?', '飞机在哪里？'),
    _Template({'where', 'police'}, 'Where is the police?', 'Di mana polis?', '警察在哪里？'),
    _Template({'where', 'store'}, 'Where is the store?', 'Di mana kedai?', '商店在哪里？'),
    _Template({'where', 'food'}, 'Where is the food?', 'Di mana makanan?', '食物在哪里？'),
    _Template({'water', 'please'}, 'Water, please.', 'Tolong air.', '请给我水。'),
    _Template({'food', 'please'}, 'Food, please.', 'Tolong makanan.', '请给我食物。'),
    _Template({'where'}, 'Where?', 'Di mana?', '在哪里？'),
    _Template({'water'}, 'Water.', 'Air.', '水。'),
    _Template({'food'}, 'I need food.', 'Saya perlu makanan.', '我需要食物。'),
    _Template({'please'}, 'Please.', 'Tolong.', '请。'),
    _Template({'thankyou'}, 'Thank you!', 'Terima kasih!', '谢谢！'),
    _Template({'bye'}, 'Goodbye!', 'Selamat tinggal!', '再见！'),
    _Template({'yes'}, 'Yes.', 'Ya.', '好的。'),
    _Template({'police'}, 'I need police.', 'Saya perlu polis.', '我需要警察。'),
    _Template({'airplane'}, 'Airplane.', 'Kapal terbang.', '飞机。'),
    _Template({'store'}, 'The store.', 'Kedai.', '商店。'),
  ];

  /// Assemble the phrase for [dialect] ('bim'|'asl') from accumulated gloss
  /// words (recognition order). The biggest matching template subset wins.
  AssembledPhrase assemble(String dialect, List<String> words) {
    final cleaned = words
        .map((w) => w.trim().toLowerCase())
        .where((w) => w.isNotEmpty)
        // Python parity: '_2' alternate-form glosses collapse to the base.
        .map((w) => w.endsWith('_2') ? w.substring(0, w.length - 2) : w)
        .toSet();
    final ordered = words
        .map((w) => w.trim().toLowerCase())
        .where((w) => w.isNotEmpty)
        .toList(growable: false);
    final sourceLang = dialect == 'asl' ? 'en' : 'ms';
    final joiner = ordered.join(' ');

    if (cleaned.isNotEmpty) {
      final table = dialect == 'asl' ? _aslTemplates : _bimTemplates;
      for (var size = cleaned.length < maxTemplateWords ? cleaned.length : maxTemplateWords;
          size > 0;
          size--) {
        for (final tpl in table) {
          if (tpl.keys.length == size && cleaned.containsAll(tpl.keys)) {
            return AssembledPhrase(
                words: ordered,
                matched: true,
                sourceLang: sourceLang,
                en: tpl.en,
                ms: tpl.ms,
                zh: tpl.zh);
          }
        }
      }
    }
    // Unmatched: the word list itself (Python fallback parity).
    return AssembledPhrase(
        words: ordered,
        matched: false,
        sourceLang: sourceLang,
        en: joiner,
        ms: joiner,
        zh: joiner);
  }
}
