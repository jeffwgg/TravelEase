# 旅遊場景詞彙 vs BIM-SIGN Pose 詞彙表覆蓋度

BIM-SIGN Pose 提供 117 個 BIM 詞彙（15,266 段片段、約 220 位簽署者、MediaPipe Holistic `(T, 258)` 關節點）。
以下將 TravelEase 旅遊溝通所需的詞彙與之比對，決定哪些直接用數據集訓練、哪些需要自錄補充。

## ✅ 直接可用（數據集已覆蓋，26 詞）

| 旅遊需求 | BIM 詞彙 (gloss_id) | 英文 |
|---|---|---|
| 廁所在哪裏 | `tandas` (108) + `mana` (69) | toilet / where |
| 醫院在哪裏 | `hospital` (48) + `mana` (69) | hospital |
| 車站 | `bas` (21) / `keretapi` (61) / `teksi` (111) | bus / train / taxi |
| 多少錢 | `berapa` (26) + `duit` (40) | how much + money |
| 去哪裏 | `pergi` (91) + `mana` (69) | go + where |
| 幫助 | `tolong` (114) | help |
| 水 / 吃 / 喝 | `air` (4) / `makan` (68) / `minum` (76) | water / eat / drink |
| 買 | `beli` (24) | buy |
| 可以嗎 | `boleh` (31) | can/may |
| 不要 | `jangan` (53) | do not |
| 什麼 / 什麼時候 | `apa` (9) / `bila` (29) | what / when |
| 謝謝 | `terima_kasih` (112) | thank you |
| 你好 | `apa_khabar` (10) / `selamat_pagi` (104) | how are you / good morning |
| 我 / 你 | `saya` (101) / `awak` (13) | I / you |
| 警察 / 消防 | `polis` (96) / `bomba` (32) | police / fire brigade |
| 疼痛 | `kesakitan` (62) | pain |
| 東西丟了 | `hilang_habis` (47) | lost |
| 商店 / 餐飲 | `kedai` (58) / `kafetaria` (56) | shop / cafeteria |
| 方向 | `arah` (11) | direction |
| 好 / 完成了 | `baik` (18) / `sudah` (106) | fine / done |
| 名字 | `nama` (79) | name |
| 雨天 / 天氣 | `hujan` (49) / `cuaca` (35) | rain / weather |

## ❌ 缺失，若要支援需自錄補充（12 詞）

| 旅遊需求 | 說明 | 優先級 |
|---|---|---|
| **左 / 右** | 核心方向詞，無替代 | P0 |
| **這個** | 指示詞，購物高頻 | P0 |
| **直走 / 轉彎** | 方向句核心 | P0 |
| **遠 / 近** | 問路常用 | P1 |
| 酒店 | 用 `kedai` 湊合度低 | P1 |
| 出口 | 機場/商場常用 | P1 |
| 門票 | 景點常用 | P1 |
| 等待 | 高頻動詞 | P2 |
| 電話 | 求助場景 | P2 |

> 決策（2026-09-05）：第一階段**不做人工補錄**，僅用數據集 117 詞。
> 「往左/右走」以 `arah`（方向）+ `pergi` 表達；方向句型保留在 templates.py，補錄後自動生效。

## 模板組句（無序關鍵詞匹配）

```python
TEMPLATES = {
    frozenset({"tandas", "mana"}):   "Di mana tandas?",        # 廁所在哪裏?
    frozenset({"hospital", "mana"}): "Di mana hospital?",      # 醫院在哪裏?
    frozenset({"pergi", "kiri"}):    "Pergi ke kiri, sila.",   # 請往左走
    frozenset({"berapa", "duit"}):   "Berapa harganya?",       # 多少錢?
    frozenset({"tolong"}):           "Tolong!",                # 幫助!
}
```

## 授權注意

- BIM-SIGN Pose：**CC BY-NC 4.0**（非商業）— demo/比賽/原型可用，商用需另談授權
- MySign (HF)：CC BY-NC-SA 4.0，1,000 詞彙 3D 動捕，第二階段擴詞彙用
- 自錄補充詞彙：授權歸 TravelEase 自己，可商用
