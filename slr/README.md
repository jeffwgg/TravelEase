# SLR — BIM 手語旅遊翻譯原型

「封閉詞彙辨識 + 模板組句」的 TravelEase 無障礙溝通原型。
方向一：聾人比手語 → 攝影機 → MediaPipe 關節點 → LSTM 分類 → 馬來語句子。
方向二：文字 → 火柴人手語動畫（關節點渲染，無需影片素材）。

## 資料

- **BIM-SIGN Pose**（[Zenodo 21631884](https://zenodo.org/records/21631884)）:
  15,266 段 × 117 詞彙 × ~220 位簽署者的 MediaPipe Holistic `(T, 258)` 關節點，
  CC BY-NC 4.0（非商業）。官方 80/10/10 split，按片段隨機切分。
- **補充自錄**（`data_custom/`，可選）: 數據集沒有的 12 個旅遊詞
  （kiri/kanan/ini/terus/pusing/jauh/dekat/hotel/keluar/tiket/tunggu/telefon）。
  詞彙覆蓋分析見 [vocab_coverage.md](vocab_coverage.md)。

## 流程

```bash
pip install -r requirements.txt

# 1. 資料下載與檢查（zip 放 slr/data/）
python scripts/verify_data.py

# 2. 訓練（CPU 可跑，40 epochs，支援 checkpoint 斷點續訓）
python scripts/train_lstm.py

# 3. 即時推理（webcam；SPACE 按住比一個詞）
python scripts/infer.py

# 3b. Gradio demo（瀏覽器開 http://127.0.0.1:7860）
#     Tab1: 手語錄影 → top-3 辨識 → 累積組句 + 語音朗讀
#     Tab2: 文字 → 火柴人手語動畫（關節點渲染，無需影片）
python scripts/demo.py

# 4. （可選，第二階段）補錄缺失詞
python scripts/record_custom.py --word kiri --signer alice
python scripts/extract_custom.py
```

## 訓練結果

- v1（無增強）: val 92.3% / test 90.0% — 乾淨數據漂亮，但真人 webcam 實測崩壞
- **v2（真實錄影增強）**: val 91.2% / test 90.6% — 乾淨數據不減，
  額外對「靜止段、變速、關節點抖動」魯棒

### 真人實測低置信度的根因（消融實驗結論）

1. 錄影含大量靜止段 → resample 後動作速度失真 → 推理端 `trim_idle` 修剪
2. Gradio 鏡像翻轉 vs 數據集未翻轉（97% → 16%）→ 推理端雙方向取高置信度
3. 真實關節點抖動（raw σ≈0.002 經肩點歸一化放大至 ~0.01）遠大於初版訓練噪聲
   （0.004）→ 加純靜止段 97% 不動、加抖動靜止段崩到 13% → 增強訓練加入
   σ∈[0.002, 0.02] 隨機噪聲 + 平滑隨機遊走仿射擾動（模擬肩點偵測漂移）

## 已知限制

- 官方 split 是隨機切分而非按簽署者切分，val/test 分數會偏樂觀；
  換真人使用時準確率會低於報告值
- 一次辨識一個詞（按鈕/錄影分段），連續手語分詞是第二階段工作
- BIM-SIGN Pose 授權為非商業；自錄部分可商用
- TTS 用印尼語音（`id`）代替馬來語（gTTS 無 `ms` 語音）

## 決策記錄

- **2026-09-05**: 第一階段不做人工補錄，僅用數據集 117 詞。
  影響：kiri/kanan/ini/terus 等方向與指示詞缺席，「往左/右走」句型無法觸發，
  以 `arah`（方向，92%）替代表達；`templates.py` 中相關句型保留但不會命中。
- **2026-09-06**: 真人實測置信度崩壞（5%），定位三層根因（見上），推理端修復
  + v2 增強重訓。⚠️ `slr/` 曾被 git clean 清掉（當時未 commit），現已納入版本控制。
