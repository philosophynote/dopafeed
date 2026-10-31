# DailyGoal（Unit 7）

## 目的
SNS には無い「止まり所」。今日の 5 本を読み切ったら宝箱が開き、満足して閉じられる。満足して閉じられると翌日も開く。
自分用アプリなので、ここは意図的に SNS と逆を行く。日付は `daily_goal.reset_hour`（午前 4 時）で切り替わる。

## 要素
1. 「DAILY GOAL」「今日の 5 本、読み切った！」（`daily_goal.articles`）
2. 宝箱（CSS / SVG。固定）
3. 「宝箱の中身」
   - 「ゴール達成ボーナス +100 XP」（未決 1）
   - 「ストリーク 4 日目 確定」（DB: ストリーク）
   - 「明日までレア確率 2 倍 P% → 2P%」（P = `xp.tiers` の rare.probability × 100。今の yml なら「25% → 50%」。モックの 16% は採らない。バフ自体と、2 倍にしたとき他の tier の確率をどう減らすかは未決 2。バフを入れないならこの行は出さない）
4. 「今日の合計 5 本 ・ 23 分 ・ 312 XP」（DB: 今日の読了数、滞在合計、XP 合計）
5. ボタン「今日はここまで」（→ Main）
6. ボタン「もう 1 本だけ（ボーナス XP は半分）」（→ Main。未決 3）
7. 注記（固定）

## 遷移
- ReadDone（5 本目の完読）→ DailyGoal（自動。未決は ReadDone の 6）
- Main のゴール表示をタップ → DailyGoal（達成前は進捗だけの軽い表示。未決 4）
- DailyGoal → Main

## 受け入れ条件（Given-When-Then）
- Given 今日 4 本完読 When 5 本目を完読 Then DailyGoal が開き「今日の 5 本、読み切った！」
- Given ゴール達成 When 宝箱を開く Then ゴール達成ボーナスが XP に加算され、2 回目は加算されない（1 日 1 回。冪等。鍵 `daily_goal.bonus_xp` が入ったら。無ければこの条件は落とす）
- Given 昨日も 1 本以上完読 When 今日達成 Then ストリークが +1 で「N 日目 確定」（定義は未決 6）
- Given 一昨日まで完読あり、昨日は 0 本 When 今日達成 Then ストリークは 1 日目
- Given reset_hour = 4 When 午前 3:59 に完読 Then 前日分として数える
- Given reset_hour = 4 When 午前 4:00 に完読 Then 当日分として数える
- Given 達成後 When 6 本目を完読 Then XP は付くが宝箱は再び出ない（ボーナス半分は鍵 `daily_goal.after_goal_xp_ratio` が入ったら。無ければ通常どおり）
- Given 今日の滞在が 23 分、XP 312 When DailyGoal を開く Then 合計欄に出る
- Given 「今日はここまで」When タップ Then Main に戻り、ステータスカードのドットが 5 個塗られている
- Given ゴール未達 When Main のゴール表示をタップ Then 宝箱は閉じたまま「あと N 本」が出る

## 使う設定の鍵
dopamine.yml: `daily_goal.articles`, `daily_goal.reset_hour`
personas.yml: なし

## 外部 API
なし

## 未決
1. ゴール達成ボーナス +100 XP。yml に鍵が無い。提案: `daily_goal.bonus_xp: 100`
2. 「明日までレア確率 2 倍」。Jackpot の未決 2 と同じバフ。第一の陣では出さない案。入れるなら rare を 2 倍にした分を common から引く（jackpot は据え置き）など、確率の合計を 1.0 に保つ規則を dopamine.yml に書く
3. 「もう 1 本だけ（ボーナス半分）」の半分の対象（基礎 XP？ ルーレット倍率？）。提案: `daily_goal.after_goal_xp_ratio: 0.5`
4. 達成前に DailyGoal を開いたときの見せ方（別画面 / Main 内の Turbo Frame）
5. `config.time_zone`（Unit 0 の持ち越し）。reset_hour の基準タイムゾーンは Asia/Tokyo にする
   → **Unit 2 で入れた**: `config.time_zone = "Tokyo"`。境界は `ReadingDay.of` / `ReadingDay.range`、宝箱の行は `daily_goals`（day unique）
6. ストリークの単位。この文書群では「1 本以上完読した日が連続」で統一（Main の「3日連続」、Install の「あと 1 本読めば継続」と一致）。モックの宝箱の「ストリーク 4 日目 確定」を「ゴール達成日が連続」と読むなら変える。main.md / install.md はここを参照
