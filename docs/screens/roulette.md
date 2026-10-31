# Roulette（Unit 6）

## 目的
可変報酬の核。「読む」を押した 0.5 秒間に XP の出目が回り、結果と同時に効果音が鳴って記事が開く。
タップ 1 回で結果が出る「報酬距離の短さ」が肝。振動は iOS Safari で使えないので、効果音と CSS アニメーションで代替する。

## 要素
1. 背景: Main を暗くしたオーバーレイ（固定）
2. 白いモーダル（角丸 28）
   - 「『読む』を押した 0.5 秒間」（固定。秒数は `xp.roulette_duration_ms`）
   - スロット: 黒い枠に各 tier の XP（`xp.base` × multiplier。今の yml なら +10 / +30 / +100）が縦に流れ、中央行がアクセント色の枠で止まる（出目は `xp.tiers` から抽選）。モックの「+10 / +25 / +15」は採らない
   - 「掘り出し物ボーナス ×K → 合計 +M XP」（抽選結果が rare のとき。K = rare.multiplier、M = `xp.base` × K。今の yml なら「×3 → 合計 +30 XP」。モックの ×1.5 / +37 は未決 1）
   - 出目表（行は `xp.tiers` の数だけ。名前・確率・倍率はすべて yml から。今の yml なら）
     - 通常（70%）: ×1 → +10 XP
     - 掘り出し物（25%）: ×3 → +30 XP
     - ジャックポット（5%）: ×10 → +100 XP
     モックは 4 段（通常 +10〜30 / 掘り出し物 8% ×1.5〜3 / 激レア 1.5% +50 / ジャックポット 0.3% ×10）だが、画面は yml の 3 段から導く。未決 1
   - 注記「結果と同時に効果音が鳴り、記事がアプリ内で開きます」（固定）

## 遷移
- Main / ReadDone の「読む」→ Roulette（Turbo Frame のモーダル。Stimulus で回転アニメーション）
- Roulette → 記事（common / rare: 0.5 秒後に自動で記事を開く）
- Roulette → Jackpot（jackpot のときは全画面演出へ。記事はその後）
- 抽選はサーバーで行い、結果を HTML に埋めて返す。クライアントは演出だけ

## 受け入れ条件（Given-When-Then）
- Given 記事カードの「読む」When タップ Then サーバーが tiers の probability に従って 1 つ抽選し、結果を Roulette に返す
- Given tiers の probability の合計が 1.0 When seed 固定の Random を注入して抽選を 10,000 回 Then 各 tier の比率が probability ± 2 ポイントに収まる（seed 固定なので結果は毎回同じ）
- Given common が出た When Roulette が止まる Then 表示 XP = xp.base × 1
- Given rare が出た When Roulette が止まる Then 「掘り出し物ボーナス ×3 → 合計 +30 XP」が出る（倍率は yml の値）
- Given jackpot が出た When Roulette が止まる Then Jackpot 画面に進む
- Given Roulette が止まった When roulette_duration_ms 経過 Then 記事が開く（Stimulus の timeout。テストでは即時）
- Given 抽選結果 When 記事を開く前にページを閉じた Then 結果は保存済みで、同じ記事を再度「読む」しても再抽選されない（冪等。未決 2）
- Given JS が動かない When 「読む」の form を POST Then 演出なしで redirect され記事が開く（通常の form POST → redirect）
- Given 効果音 When 結果が出る Then 1 回だけ鳴る（音源は未決 3。設定で切れる）

## 使う設定の鍵
dopamine.yml: `xp.base`, `xp.roulette_duration_ms`, `xp.tiers`
personas.yml: なし

## 外部 API
なし

## 未決
1. 出目の段数。モックは 4 段（通常の幅 10〜30、掘り出し物 ×1.5〜3 の幅あり）、yml は 3 段で幅なし。yml が正。幅を持たせるなら PR で提案
2. 抽選のタイミング（「読む」のタップ時 vs 読了時）。モックはタップ時（記事を開く前に XP が見える）。読了しなかった場合に XP をどう扱うか（ReadDone の「未完なら 0」と整合させる: 抽選結果は保持し、完読時に確定）
3. 効果音の音源と形式、ミュート設定の置き場所（Learning）
4. 激レア（1.5% +50 XP 紫の全画面）を tier として持つか。yml には無い
