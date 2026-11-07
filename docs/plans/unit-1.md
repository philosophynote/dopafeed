# Unit 1「モック写経」実行計画

状態: **承認済み 2026-10-31（nao）**
ブランチ: `unit-1-screens`（1 PR。docs のみ、コード変更なし。差分は docs 1,000 行前後だが全て仕様文）

## Context
画面モック（https://claude.ai/artifact/UF3JSQDBeEUGhESB3JvWyx、22 枚 + 設計メモ 8 枚）を、
以後の Unit が「仕様」として読む docs/screens/<name>.md と docs/SPEC.md に写し取る。
Unit 2（ドメインモデル）が列を決め、Unit 5〜7 が受け入れ条件をテストに写すための原本を作るのが狙い。
モックは Claude Code から Artifact tool で直接読めた（kickoff の「見えない」前提は外れた）。

決めたこと（この計画で提案、nao が承認）:
- 書く画面は SPEC の段 1〜3 の **16 枚**。段 4（NetaBox, Quest, Garden, Gacha, Hypothesis, Suggest）は
  第一の陣の対象外なので書かない。代わりに docs/screens/README.md に名前と一行だけ残す
- 深さは 2 段階。第一の陣の 7 枚（Main, ReadDone, Roulette, Jackpot, DailyGoal, Install, Login）は
  受け入れ条件を Given-When-Then で網羅する。残り 9 枚（Swipe, Comments, ForYou, Learning, Weekly, Similar,
  AddFeed, Saved, Feeds）は 目的・要素・遷移・未決 を埋め、受け入れ条件は主要な 3 本程度に留める。
  理由: Unit 2 が列を決めるには 16 枚の「要素」が要るが、受け入れ条件は実装する Unit の直前に見直すのが正確
- `config/dopamine.yml` は触らない。モックの数字と yml の差は各画面の「未決」と PR 本文の提案欄に書く
- `config/personas.yml` は作らない（Comments は第一の陣の外）。スキーマだけ docs/screens/comments.md に書く

## 現状（読んだ結果）
- docs/screens/ は _TEMPLATE.md だけ。SPEC.md の表 2 つが「Unit 1 で埋める」のまま
- dopamine.yml: base 10 / tiers common 70% ×1, rare 25% ×3, jackpot 5% ×10 / complete_after 20 秒 /
  combo +0.1 刻み上限 2.0 / daily_goal 5 本, reset 4 時 / personas_shown 3
- モックの数字は yml と食い違う箇所がある（下の「yml との差」）
- Unit 番号は milestone-1 の 10 個だけ確定。Swipe, Comments, ForYou, Learning, Weekly, Similar, AddFeed, Saved, Feeds
  の番号は無い。ファイル見出しは「（Unit 未定・第二の陣）」と書き、README に番号案を置いて nao に決めてもらう

## 手順
### 0. ブランチと計画
- `unit-1-screens`、この文書

### 1. docs/screens/README.md（索引）
- 22 画面 × 段 × Unit 番号（確定 / 未定の案）× ファイル名 の表
- モックの URL と、各ファイルがモックのどの artboard から写したか

### 2. 第一の陣の 7 枚（深く）
_TEMPLATE.md の全節を埋める。要素には「出典: 固定 / DB / dopamine.yml の鍵」を付ける。
- `main.md`: ヘッダ（設定・追加）、すべて/あなた向け切替、ストリーク・未読・読了・Lv・XP バー・今日のゴール・コンボ、
  新着バナー、カード 3 種（掘り出し物・今日限定・通常）、いいね/保存/コメント/読む、タブバー（未読バッジ）
- `read_done.md`: 滞在/推定/判定、完読ボーナス・コンボ・合計、3 行要約、ひとこと要約、今日のゴール、次の 1 本
- `roulette.md`: 0.5 秒の出目、出目表、効果音、記事を開く
- `jackpot.md`: 全画面、+XP、当たり記事、レベルアップ、24 時間レア 2 倍、閉じられない
- `daily_goal.md`: 宝箱、+100、ストリーク確定、翌日レア 2 倍、合計、今日はここまで / もう 1 本（半分）
- `install.md`: 手順 3 段、通知を許可、届く通知 3 種（7:30 / 21:00 / たまに）、バッジ
- `login.md`: パスキー + パスワード、1 年保持。パスキーは ADR 0005 と照合して「未決」に

### 3. 残り 9 枚（浅く）
- `swipe.md`, `comments.md`, `for_you.md`, `learning.md`, `weekly.md`, `similar.md`, `add_feed.md`, `saved.md`, `feeds.md`
- comments.md には personas.yml のスキーマ（id / name / title / color / description / systemPrompt の 4 部構成）と
  「AI は架空と明示」「名言の捏造禁止」「返信なし」を書く

### 4. docs/SPEC.md
- 「7 つの報酬要素 × 画面」の仕組み列を設計メモ reward から埋める（個人最適化を 8 行目に足す）
- 「iOS PWA の制約と代替策」を設計メモ pwa から埋める（振動→効果音+CSS、ウィジェット→バッジ+Push、
  Push/バッジはホーム画面追加後のみ iOS 16.4+、読了判定は戻ってきた時刻、取得は Solid Queue）
- 冒頭の「Unit 1 で写し取る」注記を「写し取り済み（Unit 1）」に

### 5. 仕上げ
- `bin/ci` 緑（docs のみなので変化なし）→ reviewer → PR（テンプレート全欄。画面欄は「docs のみ、スクショ無し」）

## yml との差（PR 本文の提案欄に写す。ここでは決めない）
| 項目 | モック | dopamine.yml |
|---|---|---|
| 出目 | 通常 +10〜30 / 掘り出し物 8% ×1.5〜3 / 激レア 1.5% +50 / ジャックポット 0.3% ×10 | common 70% ×1 / rare 25% ×3 / jackpot 5% ×10 |
| 完読の下限 | 60 秒未満は XP なし | complete_after_seconds: 20 |
| コンボ | ×2 上限、「あと 2:14」の有効時間あり | 上限 2.0、有効時間の鍵なし |
| ゴール達成 | +100 XP、もう 1 本はボーナス半分、翌日レア 2 倍 | 鍵なし |
| 今日限定 | +30 XP、残り時間 | 鍵なし |
| 通知 | 7:30 / 21:00 / 1 日最大 2 件 / ストリーク警告 3 時間前 | 鍵なし |
| Push の激レア | 1.5% | （tiers に無い） |

## 触らないもの
`config/dopamine.yml`、`config/personas.yml`（作らない）、app/ 以下、`.kamal/secrets`、`config/master.key`、`.env*`

## 検証
- docs/screens/ に 16 枚 + README、全て _TEMPLATE.md の見出しを持つ
- SPEC.md の表 2 つに空欄が無い
- 7 枚の受け入れ条件が Given-When-Then 形式で各 5 本以上
- `bin/ci` 緑

## 持ち越し
- 段 4 の 6 画面（本丸を一週間使ってから）
- Unit 番号の確定（README の案を nao が決める）
- personas.yml の実体（Comments の Unit で）
