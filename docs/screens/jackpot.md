# Jackpot（Unit 6）

## 目的
可変報酬の頂点。確率が低いからこそ効く全画面演出。読み始めるまで閉じられない。金色（ジャックポット）と紫（激レア）の 2 種。

## 要素
1. 黒背景（#141416）に紙吹雪（CSS。固定）
2. ピル「0.3% のジャックポット」（確率は `xp.tiers` の jackpot.probability）
3. 「JACKPOT」（金 #FFD166、固定）
4. 「+250」「XP ・ 通常 25 の 10 倍」（`xp.base` × jackpot.multiplier）
5. 当たり記事カード: 見出し、フィード名、約 N 分（DB）
6. チェック 3 行（固定文。数字は未決）
   - 「Lv.4 → Lv.5 にレベルアップ」（レベルは未決 1）
   - 「24 時間レア確率 2 倍」（未決 2）
   - 「激レア（1.5%）は +50 XP と紫の全画面。ジャックポットは金色」
7. ボタン「受け取って読む」（金。→ 記事）
8. 注記「全画面演出は読み始めるまで閉じられない。頻度が低いから効く」（固定）

## 遷移
- Roulette（jackpot）→ Jackpot（full page か Turbo Frame で全画面）
- Jackpot → 記事（「受け取って読む」のみ。戻るボタン・背景タップで閉じない）
- 記事 → ReadDone（通常の流れ。XP 内訳にジャックポット倍率が出る）

## 受け入れ条件（Given-When-Then）
- Given Roulette で jackpot が出た When 画面が切り替わる Then 全画面で「JACKPOT」と xp.base × multiplier の XP が出る
- Given Jackpot 画面 When 背景をタップ Then 閉じない
- Given Jackpot 画面 When 「受け取って読む」Then 記事が開き、ReadDone の内訳に jackpot 倍率が出る
- Given Jackpot 画面 When ブラウザの戻る Then Main に戻るが、抽選結果は保持され同じ記事を再度読むと Jackpot 画面が再表示される（未決 3）
- Given jackpot を引いた When 24 時間以内に次の抽選 Then レア確率が 2 倍になる（未決 2。鍵が無ければこの条件は落とす）
- Given 390 幅 When Jackpot を開く Then 紙吹雪が横スクロールを生まない

## 使う設定の鍵
dopamine.yml: `xp.base`, `xp.tiers`（jackpot の multiplier / probability）
personas.yml: なし

## 外部 API
なし

## 未決
1. レベルの閾値と表示（Main の未決 2 と同じ）
2. 「24 時間レア確率 2 倍」のバフ。dopamine.yml に鍵が無い。第一の陣では出さない案。入れるなら `xp.jackpot_buff: { hours: 24, rare_multiplier: 2 }` を PR で提案
3. 演出中に離脱したときの扱い（Roulette の未決 2 と同じ）
4. 激レア（紫）を別 tier として持つか。yml は 3 段で紫は無い（Roulette の未決 4）
