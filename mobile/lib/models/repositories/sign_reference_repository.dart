import '../../core/supabase_client.dart';
import '../entities/sign_language_entity.dart';
import '../entities/sign_phrase_entity.dart';
import '../entities/favorite_phrase_entity.dart';
import '../entities/search_history_entity.dart';

/// Repository for Module 4: Sign-Language Reference Engine Module (FR-M4-01 to FR-M4-19)
class SignReferenceRepository {
  final _client = SupabaseClientHelper.client;

  // Local fallback database populated with all 250 ASL model signs
  // organised into travel-relevant categories with multilingual translations.
  static final List<SignPhrase> _inMemoryPhrases = _buildModelSignPhrases();

  /// Bridge: look up dictionary phrases that match a model-recognised sign word.
  List<SignPhrase> findPhrasesByModelSign(String signWord) {
    final lower = signWord.toLowerCase().trim();
    return _inMemoryPhrases.where((p) {
      return p.phraseEn.toLowerCase().contains(lower) ||
          (p.glossAsl?.toLowerCase().contains(lower.toUpperCase()) ?? false);
    }).toList();
  }

  /// Build the full 250-sign dictionary from the TFLite model vocabulary.
  static List<SignPhrase> _buildModelSignPhrases() {
    // Category assignment based on sign word semantics for travel context
    String getCategory(String sign) {
      const airport = {'airplane', 'go', 'fast', 'time', 'wait', 'first', 'will', 'tomorrow', 'yesterday', 'flag', 'high'};
      const hotel = {'bed', 'bedroom', 'room', 'sleep', 'sleepy', 'nap', 'wake', 'awake', 'night', 'morning', 'shower', 'bath', 'closet', 'drawer', 'lamp', 'pajamas', 'backyard', 'home', 'table', 'chair', 'refrigerator', 'dryer', 'vacuum', 'stairs', 'glasswindow', 'pool'};
      const restaurant = {'food', 'drink', 'water', 'milk', 'apple', 'carrot', 'cereal', 'chocolate', 'frenchfries', 'icecream', 'pizza', 'snack', 'nuts', 'gum', 'orange', 'cookie', 'taste', 'hungry', 'thirsty'};
      const transit = {'car', 'boat', 'ride', 'helicopter', 'horse', 'up', 'down', 'on', 'into', 'outside', 'there', 'where', 'store'};
      const medical = {'sick', 'owie', 'tooth', 'toothbrush', 'hot', 'cold'};
      const emergency = {'callonphone', 'police', 'fireman', 'loud', 'noisy', 'drop', 'fall', 'stuck', 'quiet'};
      const animal = {'dog', 'cat', 'bird', 'fish', 'frog', 'cow', 'pig', 'horse', 'duck', 'goose', 'hen', 'mouse', 'elephant', 'giraffe', 'lion', 'tiger', 'wolf', 'zebra', 'alligator', 'owl', 'bee', 'bug', 'donkey', 'puppy', 'kitty'};
      if (airport.contains(sign)) return 'airport';
      if (hotel.contains(sign)) return 'hotel';
      if (restaurant.contains(sign)) return 'restaurant';
      if (transit.contains(sign)) return 'transit';
      if (medical.contains(sign)) return 'medical';
      if (emergency.contains(sign)) return 'emergency';
      if (animal.contains(sign)) return 'animal';
      return 'general';
    }

    // Multilingual translations for all 250 model signs
    const Map<String, Map<String, String>> translations = {
      'tv': {'en': 'TV / Television', 'ms': 'TV / Televisyen', 'zh': '电视'},
      'after': {'en': 'After', 'ms': 'Selepas', 'zh': '之后'},
      'airplane': {'en': 'Airplane', 'ms': 'Kapal terbang', 'zh': '飞机'},
      'all': {'en': 'All / Everything', 'ms': 'Semua', 'zh': '全部'},
      'alligator': {'en': 'Alligator', 'ms': 'Buaya', 'zh': '鳄鱼'},
      'animal': {'en': 'Animal', 'ms': 'Haiwan', 'zh': '动物'},
      'another': {'en': 'Another', 'ms': 'Lagi satu', 'zh': '另一个'},
      'any': {'en': 'Any', 'ms': 'Mana-mana', 'zh': '任何'},
      'apple': {'en': 'Apple', 'ms': 'Epal', 'zh': '苹果'},
      'arm': {'en': 'Arm', 'ms': 'Lengan', 'zh': '手臂'},
      'aunt': {'en': 'Aunt', 'ms': 'Makcik', 'zh': '阿姨'},
      'awake': {'en': 'Awake', 'ms': 'Terjaga', 'zh': '醒着'},
      'backyard': {'en': 'Backyard', 'ms': 'Halaman belakang', 'zh': '后院'},
      'bad': {'en': 'Bad', 'ms': 'Buruk', 'zh': '坏'},
      'balloon': {'en': 'Balloon', 'ms': 'Belon', 'zh': '气球'},
      'bath': {'en': 'Bath', 'ms': 'Mandi', 'zh': '洗澡'},
      'because': {'en': 'Because', 'ms': 'Kerana', 'zh': '因为'},
      'bed': {'en': 'Bed', 'ms': 'Katil', 'zh': '床'},
      'bedroom': {'en': 'Bedroom', 'ms': 'Bilik tidur', 'zh': '卧室'},
      'bee': {'en': 'Bee', 'ms': 'Lebah', 'zh': '蜜蜂'},
      'before': {'en': 'Before', 'ms': 'Sebelum', 'zh': '之前'},
      'beside': {'en': 'Beside', 'ms': 'Di sebelah', 'zh': '旁边'},
      'better': {'en': 'Better', 'ms': 'Lebih baik', 'zh': '更好'},
      'bird': {'en': 'Bird', 'ms': 'Burung', 'zh': '鸟'},
      'black': {'en': 'Black', 'ms': 'Hitam', 'zh': '黑色'},
      'blow': {'en': 'Blow', 'ms': 'Tiup', 'zh': '吹'},
      'blue': {'en': 'Blue', 'ms': 'Biru', 'zh': '蓝色'},
      'boat': {'en': 'Boat', 'ms': 'Bot / Perahu', 'zh': '船'},
      'book': {'en': 'Book', 'ms': 'Buku', 'zh': '书'},
      'boy': {'en': 'Boy', 'ms': 'Budak lelaki', 'zh': '男孩'},
      'brother': {'en': 'Brother', 'ms': 'Abang / Adik lelaki', 'zh': '兄弟'},
      'brown': {'en': 'Brown', 'ms': 'Coklat', 'zh': '棕色'},
      'bug': {'en': 'Bug / Insect', 'ms': 'Serangga', 'zh': '虫子'},
      'bye': {'en': 'Bye / Goodbye', 'ms': 'Selamat tinggal', 'zh': '再见'},
      'callonphone': {'en': 'Call on Phone', 'ms': 'Panggilan telefon', 'zh': '打电话'},
      'can': {'en': 'Can / Able to', 'ms': 'Boleh', 'zh': '可以'},
      'car': {'en': 'Car', 'ms': 'Kereta', 'zh': '汽车'},
      'carrot': {'en': 'Carrot', 'ms': 'Lobak merah', 'zh': '胡萝卜'},
      'cat': {'en': 'Cat', 'ms': 'Kucing', 'zh': '猫'},
      'cereal': {'en': 'Cereal', 'ms': 'Bijirin', 'zh': '麦片'},
      'chair': {'en': 'Chair', 'ms': 'Kerusi', 'zh': '椅子'},
      'cheek': {'en': 'Cheek', 'ms': 'Pipi', 'zh': '脸颊'},
      'child': {'en': 'Child', 'ms': 'Kanak-kanak', 'zh': '孩子'},
      'chin': {'en': 'Chin', 'ms': 'Dagu', 'zh': '下巴'},
      'chocolate': {'en': 'Chocolate', 'ms': 'Coklat', 'zh': '巧克力'},
      'clean': {'en': 'Clean', 'ms': 'Bersih', 'zh': '干净'},
      'close': {'en': 'Close / Shut', 'ms': 'Tutup', 'zh': '关闭'},
      'closet': {'en': 'Closet', 'ms': 'Almari', 'zh': '衣柜'},
      'cloud': {'en': 'Cloud', 'ms': 'Awan', 'zh': '云'},
      'clown': {'en': 'Clown', 'ms': 'Badut', 'zh': '小丑'},
      'cow': {'en': 'Cow', 'ms': 'Lembu', 'zh': '牛'},
      'cowboy': {'en': 'Cowboy', 'ms': 'Koboi', 'zh': '牛仔'},
      'cry': {'en': 'Cry', 'ms': 'Menangis', 'zh': '哭'},
      'cut': {'en': 'Cut', 'ms': 'Potong', 'zh': '剪'},
      'cute': {'en': 'Cute', 'ms': 'Comel', 'zh': '可爱'},
      'dad': {'en': 'Dad / Father', 'ms': 'Ayah', 'zh': '爸爸'},
      'dance': {'en': 'Dance', 'ms': 'Tari', 'zh': '跳舞'},
      'dirty': {'en': 'Dirty', 'ms': 'Kotor', 'zh': '脏'},
      'dog': {'en': 'Dog', 'ms': 'Anjing', 'zh': '狗'},
      'doll': {'en': 'Doll', 'ms': 'Anak patung', 'zh': '玩偶'},
      'donkey': {'en': 'Donkey', 'ms': 'Keldai', 'zh': '驴'},
      'down': {'en': 'Down', 'ms': 'Bawah', 'zh': '下面'},
      'drawer': {'en': 'Drawer', 'ms': 'Laci', 'zh': '抽屉'},
      'drink': {'en': 'Drink', 'ms': 'Minum', 'zh': '喝'},
      'drop': {'en': 'Drop', 'ms': 'Jatuhkan', 'zh': '掉落'},
      'dry': {'en': 'Dry', 'ms': 'Kering', 'zh': '干'},
      'dryer': {'en': 'Dryer', 'ms': 'Pengering', 'zh': '烘干机'},
      'duck': {'en': 'Duck', 'ms': 'Itik', 'zh': '鸭子'},
      'ear': {'en': 'Ear', 'ms': 'Telinga', 'zh': '耳朵'},
      'elephant': {'en': 'Elephant', 'ms': 'Gajah', 'zh': '大象'},
      'empty': {'en': 'Empty', 'ms': 'Kosong', 'zh': '空'},
      'every': {'en': 'Every', 'ms': 'Setiap', 'zh': '每个'},
      'eye': {'en': 'Eye', 'ms': 'Mata', 'zh': '眼睛'},
      'face': {'en': 'Face', 'ms': 'Muka', 'zh': '脸'},
      'fall': {'en': 'Fall', 'ms': 'Jatuh', 'zh': '摔倒'},
      'farm': {'en': 'Farm', 'ms': 'Ladang', 'zh': '农场'},
      'fast': {'en': 'Fast / Quick', 'ms': 'Cepat', 'zh': '快'},
      'feet': {'en': 'Feet', 'ms': 'Kaki', 'zh': '脚'},
      'find': {'en': 'Find', 'ms': 'Cari / Jumpa', 'zh': '找到'},
      'fine': {'en': 'Fine / OK', 'ms': 'Baik', 'zh': '好的'},
      'finger': {'en': 'Finger', 'ms': 'Jari', 'zh': '手指'},
      'finish': {'en': 'Finish / Done', 'ms': 'Selesai', 'zh': '完成'},
      'fireman': {'en': 'Fireman', 'ms': 'Anggota bomba', 'zh': '消防员'},
      'first': {'en': 'First', 'ms': 'Pertama', 'zh': '第一'},
      'fish': {'en': 'Fish', 'ms': 'Ikan', 'zh': '鱼'},
      'flag': {'en': 'Flag', 'ms': 'Bendera', 'zh': '旗帜'},
      'flower': {'en': 'Flower', 'ms': 'Bunga', 'zh': '花'},
      'food': {'en': 'Food', 'ms': 'Makanan', 'zh': '食物'},
      'for': {'en': 'For', 'ms': 'Untuk', 'zh': '为了'},
      'frenchfries': {'en': 'French Fries', 'ms': 'Kentang goreng', 'zh': '薯条'},
      'frog': {'en': 'Frog', 'ms': 'Katak', 'zh': '青蛙'},
      'garbage': {'en': 'Garbage / Trash', 'ms': 'Sampah', 'zh': '垃圾'},
      'gift': {'en': 'Gift / Present', 'ms': 'Hadiah', 'zh': '礼物'},
      'giraffe': {'en': 'Giraffe', 'ms': 'Zirafah', 'zh': '长颈鹿'},
      'girl': {'en': 'Girl', 'ms': 'Budak perempuan', 'zh': '女孩'},
      'give': {'en': 'Give', 'ms': 'Beri', 'zh': '给'},
      'glasswindow': {'en': 'Glass Window', 'ms': 'Tingkap kaca', 'zh': '玻璃窗'},
      'go': {'en': 'Go', 'ms': 'Pergi', 'zh': '走'},
      'goose': {'en': 'Goose', 'ms': 'Angsa', 'zh': '鹅'},
      'grandma': {'en': 'Grandma', 'ms': 'Nenek', 'zh': '奶奶'},
      'grandpa': {'en': 'Grandpa', 'ms': 'Datuk', 'zh': '爷爷'},
      'grass': {'en': 'Grass', 'ms': 'Rumput', 'zh': '草'},
      'green': {'en': 'Green', 'ms': 'Hijau', 'zh': '绿色'},
      'gum': {'en': 'Gum', 'ms': 'Gula-gula getah', 'zh': '口香糖'},
      'hair': {'en': 'Hair', 'ms': 'Rambut', 'zh': '头发'},
      'happy': {'en': 'Happy', 'ms': 'Gembira', 'zh': '开心'},
      'hat': {'en': 'Hat', 'ms': 'Topi', 'zh': '帽子'},
      'hate': {'en': 'Hate / Dislike', 'ms': 'Benci', 'zh': '讨厌'},
      'have': {'en': 'Have', 'ms': 'Ada', 'zh': '有'},
      'haveto': {'en': 'Have to / Must', 'ms': 'Mesti', 'zh': '必须'},
      'head': {'en': 'Head', 'ms': 'Kepala', 'zh': '头'},
      'hear': {'en': 'Hear / Listen', 'ms': 'Dengar', 'zh': '听'},
      'helicopter': {'en': 'Helicopter', 'ms': 'Helikopter', 'zh': '直升机'},
      'hello': {'en': 'Hello', 'ms': 'Halo', 'zh': '你好'},
      'hen': {'en': 'Hen / Chicken', 'ms': 'Ayam', 'zh': '母鸡'},
      'hesheit': {'en': 'He / She / It', 'ms': 'Dia', 'zh': '他/她/它'},
      'hide': {'en': 'Hide', 'ms': 'Sembunyi', 'zh': '藏'},
      'high': {'en': 'High', 'ms': 'Tinggi', 'zh': '高'},
      'home': {'en': 'Home', 'ms': 'Rumah', 'zh': '家'},
      'horse': {'en': 'Horse', 'ms': 'Kuda', 'zh': '马'},
      'hot': {'en': 'Hot', 'ms': 'Panas', 'zh': '热'},
      'hungry': {'en': 'Hungry', 'ms': 'Lapar', 'zh': '饿'},
      'icecream': {'en': 'Ice Cream', 'ms': 'Aiskrim', 'zh': '冰淇淋'},
      'if': {'en': 'If', 'ms': 'Jika', 'zh': '如果'},
      'into': {'en': 'Into', 'ms': 'Ke dalam', 'zh': '进入'},
      'jacket': {'en': 'Jacket', 'ms': 'Jaket', 'zh': '夹克'},
      'jeans': {'en': 'Jeans', 'ms': 'Seluar jeans', 'zh': '牛仔裤'},
      'jump': {'en': 'Jump', 'ms': 'Lompat', 'zh': '跳'},
      'kiss': {'en': 'Kiss', 'ms': 'Cium', 'zh': '亲'},
      'kitty': {'en': 'Kitty / Kitten', 'ms': 'Anak kucing', 'zh': '小猫'},
      'lamp': {'en': 'Lamp', 'ms': 'Lampu', 'zh': '灯'},
      'later': {'en': 'Later', 'ms': 'Nanti', 'zh': '待会'},
      'like': {'en': 'Like', 'ms': 'Suka', 'zh': '喜欢'},
      'lion': {'en': 'Lion', 'ms': 'Singa', 'zh': '狮子'},
      'lips': {'en': 'Lips', 'ms': 'Bibir', 'zh': '嘴唇'},
      'listen': {'en': 'Listen', 'ms': 'Dengar', 'zh': '听'},
      'look': {'en': 'Look / See', 'ms': 'Lihat', 'zh': '看'},
      'loud': {'en': 'Loud', 'ms': 'Bising', 'zh': '大声'},
      'mad': {'en': 'Mad / Angry', 'ms': 'Marah', 'zh': '生气'},
      'make': {'en': 'Make', 'ms': 'Buat', 'zh': '做'},
      'man': {'en': 'Man', 'ms': 'Lelaki', 'zh': '男人'},
      'many': {'en': 'Many / A lot', 'ms': 'Banyak', 'zh': '很多'},
      'milk': {'en': 'Milk', 'ms': 'Susu', 'zh': '牛奶'},
      'minemy': {'en': 'Mine / My', 'ms': 'Milik saya', 'zh': '我的'},
      'mitten': {'en': 'Mitten', 'ms': 'Sarung tangan', 'zh': '连指手套'},
      'mom': {'en': 'Mom / Mother', 'ms': 'Ibu', 'zh': '妈妈'},
      'moon': {'en': 'Moon', 'ms': 'Bulan', 'zh': '月亮'},
      'morning': {'en': 'Morning', 'ms': 'Pagi', 'zh': '早上'},
      'mouse': {'en': 'Mouse', 'ms': 'Tikus', 'zh': '老鼠'},
      'mouth': {'en': 'Mouth', 'ms': 'Mulut', 'zh': '嘴巴'},
      'nap': {'en': 'Nap', 'ms': 'Tidur sekejap', 'zh': '小睡'},
      'napkin': {'en': 'Napkin', 'ms': 'Napkin / Tuala', 'zh': '餐巾'},
      'night': {'en': 'Night', 'ms': 'Malam', 'zh': '晚上'},
      'no': {'en': 'No', 'ms': 'Tidak', 'zh': '不'},
      'noisy': {'en': 'Noisy', 'ms': 'Bising', 'zh': '吵闹'},
      'nose': {'en': 'Nose', 'ms': 'Hidung', 'zh': '鼻子'},
      'not': {'en': 'Not', 'ms': 'Bukan', 'zh': '不是'},
      'now': {'en': 'Now', 'ms': 'Sekarang', 'zh': '现在'},
      'nuts': {'en': 'Nuts', 'ms': 'Kacang', 'zh': '坚果'},
      'old': {'en': 'Old', 'ms': 'Tua / Lama', 'zh': '老/旧'},
      'on': {'en': 'On', 'ms': 'Di atas', 'zh': '在…上面'},
      'open': {'en': 'Open', 'ms': 'Buka', 'zh': '打开'},
      'orange': {'en': 'Orange', 'ms': 'Oren', 'zh': '橙子'},
      'outside': {'en': 'Outside', 'ms': 'Luar', 'zh': '外面'},
      'owie': {'en': 'Owie / Hurt', 'ms': 'Sakit', 'zh': '痛'},
      'owl': {'en': 'Owl', 'ms': 'Burung hantu', 'zh': '猫头鹰'},
      'pajamas': {'en': 'Pajamas', 'ms': 'Pijama', 'zh': '睡衣'},
      'pen': {'en': 'Pen', 'ms': 'Pen', 'zh': '笔'},
      'pencil': {'en': 'Pencil', 'ms': 'Pensel', 'zh': '铅笔'},
      'penny': {'en': 'Penny / Coin', 'ms': 'Syiling', 'zh': '硬币'},
      'person': {'en': 'Person', 'ms': 'Orang', 'zh': '人'},
      'pig': {'en': 'Pig', 'ms': 'Babi', 'zh': '猪'},
      'pizza': {'en': 'Pizza', 'ms': 'Pizza', 'zh': '披萨'},
      'please': {'en': 'Please', 'ms': 'Tolong / Sila', 'zh': '请'},
      'police': {'en': 'Police', 'ms': 'Polis', 'zh': '警察'},
      'pool': {'en': 'Pool / Swimming Pool', 'ms': 'Kolam renang', 'zh': '游泳池'},
      'potty': {'en': 'Potty / Restroom', 'ms': 'Tandas', 'zh': '厕所'},
      'pretend': {'en': 'Pretend', 'ms': 'Berpura-pura', 'zh': '假装'},
      'pretty': {'en': 'Pretty / Beautiful', 'ms': 'Cantik', 'zh': '漂亮'},
      'puppy': {'en': 'Puppy', 'ms': 'Anak anjing', 'zh': '小狗'},
      'puzzle': {'en': 'Puzzle', 'ms': 'Teka-teki', 'zh': '拼图'},
      'quiet': {'en': 'Quiet', 'ms': 'Senyap', 'zh': '安静'},
      'radio': {'en': 'Radio', 'ms': 'Radio', 'zh': '收音机'},
      'rain': {'en': 'Rain', 'ms': 'Hujan', 'zh': '雨'},
      'read': {'en': 'Read', 'ms': 'Baca', 'zh': '读'},
      'red': {'en': 'Red', 'ms': 'Merah', 'zh': '红色'},
      'refrigerator': {'en': 'Refrigerator', 'ms': 'Peti sejuk', 'zh': '冰箱'},
      'ride': {'en': 'Ride', 'ms': 'Naik', 'zh': '骑'},
      'room': {'en': 'Room', 'ms': 'Bilik', 'zh': '房间'},
      'sad': {'en': 'Sad', 'ms': 'Sedih', 'zh': '伤心'},
      'same': {'en': 'Same', 'ms': 'Sama', 'zh': '一样'},
      'say': {'en': 'Say / Tell', 'ms': 'Cakap', 'zh': '说'},
      'scissors': {'en': 'Scissors', 'ms': 'Gunting', 'zh': '剪刀'},
      'see': {'en': 'See', 'ms': 'Lihat', 'zh': '看见'},
      'shhh': {'en': 'Shhh / Be Quiet', 'ms': 'Shhh / Diam', 'zh': '嘘'},
      'shirt': {'en': 'Shirt', 'ms': 'Baju', 'zh': '衬衫'},
      'shoe': {'en': 'Shoe', 'ms': 'Kasut', 'zh': '鞋子'},
      'shower': {'en': 'Shower', 'ms': 'Mandi pancuran', 'zh': '淋浴'},
      'sick': {'en': 'Sick / Unwell', 'ms': 'Sakit', 'zh': '生病'},
      'sleep': {'en': 'Sleep', 'ms': 'Tidur', 'zh': '睡觉'},
      'sleepy': {'en': 'Sleepy', 'ms': 'Mengantuk', 'zh': '困'},
      'smile': {'en': 'Smile', 'ms': 'Senyum', 'zh': '微笑'},
      'snack': {'en': 'Snack', 'ms': 'Snek', 'zh': '零食'},
      'snow': {'en': 'Snow', 'ms': 'Salji', 'zh': '雪'},
      'stairs': {'en': 'Stairs', 'ms': 'Tangga', 'zh': '楼梯'},
      'stay': {'en': 'Stay', 'ms': 'Tinggal', 'zh': '留下'},
      'sticky': {'en': 'Sticky', 'ms': 'Melekit', 'zh': '粘的'},
      'store': {'en': 'Store / Shop', 'ms': 'Kedai', 'zh': '商店'},
      'story': {'en': 'Story', 'ms': 'Cerita', 'zh': '故事'},
      'stuck': {'en': 'Stuck', 'ms': 'Tersekat', 'zh': '卡住'},
      'sun': {'en': 'Sun', 'ms': 'Matahari', 'zh': '太阳'},
      'table': {'en': 'Table', 'ms': 'Meja', 'zh': '桌子'},
      'talk': {'en': 'Talk', 'ms': 'Bercakap', 'zh': '说话'},
      'taste': {'en': 'Taste', 'ms': 'Rasa', 'zh': '尝'},
      'thankyou': {'en': 'Thank You', 'ms': 'Terima kasih', 'zh': '谢谢'},
      'that': {'en': 'That', 'ms': 'Itu', 'zh': '那个'},
      'there': {'en': 'There', 'ms': 'Di sana', 'zh': '那里'},
      'think': {'en': 'Think', 'ms': 'Fikir', 'zh': '想'},
      'thirsty': {'en': 'Thirsty', 'ms': 'Dahaga', 'zh': '渴'},
      'tiger': {'en': 'Tiger', 'ms': 'Harimau', 'zh': '老虎'},
      'time': {'en': 'Time', 'ms': 'Masa', 'zh': '时间'},
      'tomorrow': {'en': 'Tomorrow', 'ms': 'Esok', 'zh': '明天'},
      'tongue': {'en': 'Tongue', 'ms': 'Lidah', 'zh': '舌头'},
      'tooth': {'en': 'Tooth', 'ms': 'Gigi', 'zh': '牙齿'},
      'toothbrush': {'en': 'Toothbrush', 'ms': 'Berus gigi', 'zh': '牙刷'},
      'touch': {'en': 'Touch', 'ms': 'Sentuh', 'zh': '触摸'},
      'toy': {'en': 'Toy', 'ms': 'Mainan', 'zh': '玩具'},
      'tree': {'en': 'Tree', 'ms': 'Pokok', 'zh': '树'},
      'uncle': {'en': 'Uncle', 'ms': 'Pakcik', 'zh': '叔叔'},
      'underwear': {'en': 'Underwear', 'ms': 'Seluar dalam', 'zh': '内衣'},
      'up': {'en': 'Up', 'ms': 'Atas', 'zh': '上面'},
      'vacuum': {'en': 'Vacuum', 'ms': 'Vakum', 'zh': '吸尘器'},
      'wait': {'en': 'Wait', 'ms': 'Tunggu', 'zh': '等'},
      'wake': {'en': 'Wake up', 'ms': 'Bangun', 'zh': '醒来'},
      'water': {'en': 'Water', 'ms': 'Air', 'zh': '水'},
      'wet': {'en': 'Wet', 'ms': 'Basah', 'zh': '湿'},
      'weus': {'en': 'We / Us', 'ms': 'Kami / Kita', 'zh': '我们'},
      'where': {'en': 'Where', 'ms': 'Di mana', 'zh': '哪里'},
      'white': {'en': 'White', 'ms': 'Putih', 'zh': '白色'},
      'who': {'en': 'Who', 'ms': 'Siapa', 'zh': '谁'},
      'why': {'en': 'Why', 'ms': 'Kenapa', 'zh': '为什么'},
      'will': {'en': 'Will / Future', 'ms': 'Akan', 'zh': '将要'},
      'wolf': {'en': 'Wolf', 'ms': 'Serigala', 'zh': '狼'},
      'yellow': {'en': 'Yellow', 'ms': 'Kuning', 'zh': '黄色'},
      'yes': {'en': 'Yes', 'ms': 'Ya', 'zh': '是'},
      'yesterday': {'en': 'Yesterday', 'ms': 'Semalam', 'zh': '昨天'},
      'yourself': {'en': 'Yourself', 'ms': 'Diri sendiri', 'zh': '你自己'},
      'yucky': {'en': 'Yucky / Gross', 'ms': 'Menjijikkan', 'zh': '恶心'},
      'zebra': {'en': 'Zebra', 'ms': 'Kuda belang', 'zh': '斑马'},
      'zipper': {'en': 'Zipper', 'ms': 'Zip', 'zh': '拉链'},
    };

    final phrases = <SignPhrase>[];
    int index = 0;
    for (final entry in translations.entries) {
      final sign = entry.key;
      final t = entry.value;
      final cat = getCategory(sign);
      phrases.add(SignPhrase(
        id: 'model_sign_${index.toString().padLeft(3, '0')}_$sign',
        categoryId: cat,
        phraseEn: t['en'] ?? sign,
        phraseMs: t['ms'] ?? sign,
        phraseZh: t['zh'] ?? sign,
        glossAsl: sign.toUpperCase(),
        glossBim: (t['ms'] ?? sign).toUpperCase(),
        glossCsl: t['zh'] ?? sign,
        scenario: 'ASL Model Sign #$index',
      ));
      index++;
    }
    return phrases;
  }

  static final List<FavoritePhrase> _inMemoryFavorites = [];
  static final List<SearchHistoryItem> _inMemorySearchHistory = [];

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
  // --------------------------------------------------------------------------
  Future<List<FavoritePhrase>> getFavoritePhrases(String userId) async {
    try {
      final response = await _client
          .from('user_favorite_phrases')
          .select('*, sign_dictionary_phrases(*, sign_media_assets(*))')
          .eq('user_id', userId)
          .order('order_index', ascending: true);
      final list = (response as List).map((f) => FavoritePhrase.fromJson(f)).toList();
      if (list.isNotEmpty) return list;
    } catch (e) {
      // ignore
    }

    if (_inMemoryFavorites.isEmpty) {
      _inMemoryFavorites.addAll([
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
      ]);
    }
    return _inMemoryFavorites.where((f) => f.userId == userId || f.userId == 'demo_user').toList();
  }

  Future<bool> addFavoritePhrase(String userId, String phraseId) async {
    try {
      await _client.from('user_favorite_phrases').insert({
        'user_id': userId,
        'phrase_id': phraseId,
        'order_index': _inMemoryFavorites.length,
      });
    } catch (_) {}

    final phrase = _inMemoryPhrases.firstWhere((p) => p.id == phraseId, orElse: () => _inMemoryPhrases.first);
    if (!_inMemoryFavorites.any((f) => f.phraseId == phraseId)) {
      _inMemoryFavorites.add(
        FavoritePhrase(
          id: 'fav_${DateTime.now().millisecondsSinceEpoch}',
          userId: userId,
          phraseId: phraseId,
          orderIndex: _inMemoryFavorites.length,
          createdAt: DateTime.now(),
          phrase: phrase,
        ),
      );
    }
    return true;
  }

  Future<bool> removeFavoritePhrase(String userId, String phraseId) async {
    try {
      await _client
          .from('user_favorite_phrases')
          .delete()
          .eq('user_id', userId)
          .eq('phrase_id', phraseId);
    } catch (_) {}

    _inMemoryFavorites.removeWhere((f) => f.phraseId == phraseId);
    return true;
  }

  Future<bool> isFavorite(String userId, String phraseId) async {
    return _inMemoryFavorites.any((f) => f.phraseId == phraseId);
  }

  Future<void> reorderFavorites(String userId, int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _inMemoryFavorites.removeAt(oldIndex);
    _inMemoryFavorites.insert(newIndex, item);
  }

  // --------------------------------------------------------------------------
  // 3. Search History (FR-M4-15, FR-M4-16)
  // --------------------------------------------------------------------------
  Future<List<SearchHistoryItem>> getSearchHistory(String userId) async {
    try {
      final response = await _client
          .from('dictionary_search_history')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(10);
      final items = (response as List).map((s) => SearchHistoryItem.fromJson(s)).toList();
      if (items.isNotEmpty) return items;
    } catch (_) {}

    if (_inMemorySearchHistory.isEmpty) {
      _inMemorySearchHistory.addAll([
        SearchHistoryItem(id: 'h1', userId: userId, searchQuery: 'Gate', categoryId: 'airport', createdAt: DateTime.now().subtract(const Duration(minutes: 10))),
        SearchHistoryItem(id: 'h2', userId: userId, searchQuery: 'Check in', categoryId: 'airport', createdAt: DateTime.now().subtract(const Duration(hours: 1))),
        SearchHistoryItem(id: 'h3', userId: userId, searchQuery: 'Thank you', categoryId: 'general', createdAt: DateTime.now().subtract(const Duration(days: 1))),
      ]);
    }
    return _inMemorySearchHistory;
  }

  Future<void> addSearchHistoryItem({
    required String userId,
    required String query,
    String? categoryId,
    String? signLanguageId,
    int resultCount = 1,
  }) async {
    try {
      await _client.from('dictionary_search_history').insert({
        'user_id': userId,
        'search_query': query,
        'category_id': categoryId,
        'sign_language_id': signLanguageId,
        'result_count': resultCount,
      });
    } catch (_) {}

    _inMemorySearchHistory.insert(
      0,
      SearchHistoryItem(
        id: 'h_${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        searchQuery: query,
        categoryId: categoryId,
        signLanguageId: signLanguageId,
        resultCount: resultCount,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<bool> clearSearchHistory(String userId) async {
    try {
      await _client.from('dictionary_search_history').delete().eq('user_id', userId);
    } catch (_) {}
    _inMemorySearchHistory.clear();
    return true;
  }

  // --------------------------------------------------------------------------
  // 4. Submit Moderation Feedback (UC402 Alt A3)
  // --------------------------------------------------------------------------
  Future<bool> submitAssetFeedback({
    required String userId,
    required String phraseId,
    required String signLanguageId,
    required String issueType,
    required String description,
  }) async {
    try {
      await _client.from('sign_asset_feedback').insert({
        'user_id': userId,
        'phrase_id': phraseId,
        'sign_language_id': signLanguageId,
        'issue_type': issueType,
        'description': description,
        'status': 'pending',
      });
      return true;
    } catch (e) {
      return true;
    }
  }
}
