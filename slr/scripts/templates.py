"""Sentence templates: unordered keyword sets -> Malay sentence + Chinese.

Recognition returns a set of BIM glosses (BIM grammar differs from Malay, so
we match keyword sets, not sequences). Unmatched combinations fall back to
listing the recognized words.
"""

from dataclasses import dataclass


@dataclass
class Utterance:
    malay: str
    chinese: str
    matched: bool


TEMPLATES = {
    # --- asking for places ---
    frozenset({"tandas", "mana"}): Utterance("Di mana tandas?", "廁所在哪裏?", True),
    frozenset({"hospital", "mana"}): Utterance("Di mana hospital?", "醫院在哪裏?", True),
    frozenset({"polis", "mana"}): Utterance("Di mana balai polis?", "警察局在哪裏?", True),
    frozenset({"kedai", "mana"}): Utterance("Di mana kedai?", "商店在哪裏?", True),
    frozenset({"kafetaria", "mana"}): Utterance("Di mana kafetaria?", "餐廳在哪裏?", True),
    frozenset({"bas", "mana"}): Utterance("Di mana stesen bas?", "巴士站在哪裏?", True),
    frozenset({"keretapi", "mana"}): Utterance("Di mana stesen keretapi?", "火車站在哪裏?", True),
    frozenset({"teksi", "mana"}): Utterance("Di mana boleh naik teksi?", "哪裏可以搭計程車?", True),
    # --- directions ---
    frozenset({"pergi", "kiri"}): Utterance("Sila pergi ke kiri.", "請往左邊走。", True),
    frozenset({"pergi", "kanan"}): Utterance("Sila pergi ke kanan.", "請往右邊走。", True),
    frozenset({"pergi", "terus"}): Utterance("Terus jalan sahaja.", "請一直往前走。", True),
    frozenset({"pergi", "pusing", "kiri"}): Utterance("Pusing ke kiri di hadapan.", "前面左轉。", True),
    frozenset({"pergi", "pusing", "kanan"}): Utterance("Pusing ke kanan di hadapan.", "前面右轉。", True),
    frozenset({"pergi", "arah"}): Utterance("Jalan ikut arah ini.", "往這個方向走。", True),
    # --- shopping ---
    frozenset({"berapa", "duit"}): Utterance("Berapa harganya?", "請問多少錢?", True),
    frozenset({"harga"}): Utterance("Berapa harganya?", "請問多少錢?", True),
    frozenset({"harga", "ini"}): Utterance("Berapa harga yang ini?", "請問這個多少錢?", True),
    frozenset({"ini", "berapa"}): Utterance("Berapa harga yang ini?", "請問這個多少錢?", True),
    frozenset({"beli", "ini"}): Utterance("Saya nak beli yang ini.", "我想買這個。", True),
    frozenset({"mahal"}): Utterance("Terlalu mahal.", "太貴了。", True),
    frozenset({"beli", "tiket"}): Utterance("Saya nak beli tiket.", "我想買票。", True),
    # --- needs ---
    frozenset({"tolong"}): Utterance("Tolong! Saya perlukan bantuan.", "幫助!我需要幫忙。", True),
    frozenset({"minum", "air"}): Utterance("Boleh saya dapatkan air?", "可以給我一杯水嗎?", True),
    frozenset({"makan"}): Utterance("Saya lapar, nak makan.", "我餓了,想吃東西。", True),
    frozenset({"makan", "mana"}): Utterance("Di mana boleh makan?", "哪裏可以吃飯?", True),
    frozenset({"jangan"}): Utterance("Tidak, terima kasih.", "不用了,謝謝。", True),
    frozenset({"boleh"}): Utterance("Boleh tak?", "可以嗎?", True),
    # --- emergency ---
    frozenset({"kesakitan"}): Utterance("Saya sakit.", "我痛/不舒服。", True),
    frozenset({"hilang_habis"}): Utterance("Barang saya hilang.", "我的東西不見了。", True),
    frozenset({"telefon"}): Utterance("Boleh pinjam telefon?", "可以借電話嗎?", True),
    # --- social ---
    frozenset({"terima_kasih"}): Utterance("Terima kasih!", "謝謝!", True),
    frozenset({"apa_khabar"}): Utterance("Apa khabar?", "你好嗎?", True),
    frozenset({"selamat_pagi"}): Utterance("Selamat pagi!", "早安!", True),
    frozenset({"nama", "saya"}): Utterance("Nama saya...", "我的名字是...", True),
    frozenset({"bila"}): Utterance("Bila?", "什麼時候?", True),
    frozenset({"apa"}): Utterance("Apa ini?", "這是什麼?", True),
}

MAX_TEMPLATE_WORDS = 3


def glosses_to_utterance(glosses):
    """Match recognized glosses (unordered) to the best template."""
    keys = {g for g in glosses if not g.endswith("_2")}  # drop alt-form suffixes
    if not keys:
        return Utterance("", "（沒有辨識到內容）", False)
    for size in range(min(len(keys), MAX_TEMPLATE_WORDS), 0, -1):
        for combo in _subsets(keys, size):
            if combo in TEMPLATES:
                return TEMPLATES[combo]
    malay = " ".join(sorted(keys))
    chinese = "、".join(sorted(keys)) + "（未匹配句型，朗讀詞彙）"
    return Utterance(malay, chinese, False)


def _subsets(keys, size):
    keys = list(keys)
    result = []

    def go(start, acc):
        if len(acc) == size:
            result.append(frozenset(acc))
            return
        for i in range(start, len(keys)):
            go(i + 1, acc + [keys[i]])
    go(0, [])
    return result


if __name__ == "__main__":
    tests = [
        ["tandas", "mana"],
        ["mana", "tandas"],
        ["berapa", "duit", "apa"],
        ["pergi", "kiri"],
        ["tolong"],
        ["bola"],
    ]
    for t in tests:
        u = glosses_to_utterance(t)
        print(f"{t} -> [{u.malay}] [{u.chinese}] matched={u.matched}")
