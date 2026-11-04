# ReadDone（Unit 5）

> **#43（ADR 0010）で Reader の区切りに畳んだ。** 元サイトへ出て戻る経路と full page の ReadDone（`GET /readings/:id`）は無い。判定・滞在・XP・コンボ・今日のゴールは docs/screens/reader.md の要素 4（区切り）が出す。3 行要約と「次の 1 本」は、本文と継ぎ足される次の記事が代わる。以下は Unit 5 の記録として残す。

## 目的
「止まり所」と「報酬距離」を担う。記事から戻ってきた瞬間に、滞在時間・判定・XP の内訳・3 行要約を一枚で見せ、
「閉じる」が次の「開く」になる構造（次の 1 本を下に置く）で無限供給へ繋ぐ。ドゥームスクロールにならないよう、滞在が短ければ XP を出さない。

## 要素
1. 見出し「読了！」と「5 本連続 ・ コンボ ×2」（DB: 連続完読数。倍率は 1 + `xp.combo_multiplier_step` × 連続数、上限 `xp.combo_max_multiplier`。「連続」の定義は未決 7）
2. 記事タイトル（DB）
3. 計測 3 枚: 「滞在 4分12秒」（DB: 開いた時刻と戻った時刻の差）、「推定読了 3分」（未決 1）、「判定 完読」（`read.complete_after_seconds` 以上なら完読）
4. XP 内訳（3 行とも導出値。モックの +40 / +40 / +80 は採らない）: 「完読ボーナス +A XP」（A = `xp.base` × ルーレットの tier.multiplier）、「コンボ ×C +B XP」（C = コンボ倍率、B = A × (C − 1)）、「合計 +A×C XP」。今の yml で rare・コンボ ×2 なら「+30」「×2 +30」「合計 +60」
5. 注記「記事を開いてアプリに戻るまでの時間で計測。S 秒未満なら XP なし」（S = `read.complete_after_seconds` を描画時に埋める。今の yml なら「20 秒未満」。モックの 60 は採らない。未決 2）
6. 「Claude の 3 行要約（claude-haiku-5-5 ・ 約 ¥0.3）」と 3 行（DB: summary。モデル名は `claude.summary_model`。金額は出さない案、未決 3）
7. 「ひとこと要約を残す ＋10 XP」textarea（DB: 未決 4。XP は dopamine.yml に鍵が無い）
8. ボタン「保存して ガチャへ」（→ Gacha。段 4 なので第一の陣では「保存して閉じる」→ Main）、「ネタにする」（→ NetaBox。第一の陣では出さない）
9. 「今日のゴール 4 / 5 ・ あと 1 本で宝箱」（→ DailyGoal。`daily_goal.articles`）
10. 「次の 1 本 ・ 上にスワイプで開く」カード: フィード名・約 N 分・見出し（DB: 次の未読）。スワイプで次の記事の Roulette へ

## 遷移
- 記事（PWA 内のブラウザシート）→ 戻る → ReadDone（full page か Turbo Frame。未決 5）
- ReadDone → Main（閉じる / 保存して閉じる）。読んだカードは消え、ステータスが更新される
- ReadDone → DailyGoal（5 本目の読了なら自動で。それ以外はタップ）
- ReadDone → Roulette（次の 1 本を上スワイプ）
- ReadDone → Gacha / NetaBox（段 4。第一の陣では無い）

## 受け入れ条件（Given-When-Then）
- Given 記事を開いて complete_after_seconds + 5 秒後に戻った When ReadDone を開く Then 判定「完読」で XP が付く
- Given 記事を開いて complete_after_seconds − 10 秒後に戻った When ReadDone を開く Then 判定「未完」で合計 +0 XP、ストリークとゴールに数えない
- Given 完読、ルーレット倍率 ×1、コンボ無し When ReadDone を開く Then 合計 = xp.base
- Given 完読、同日内（reset_hour 基準）で直前に 2 本連続完読し間に未完読が無い When ReadDone を開く Then コンボ倍率 = 1 + combo_multiplier_step × 2 で内訳に出る
- Given 同日内に連続 20 本完読 When ReadDone を開く Then コンボ倍率は combo_max_multiplier で頭打ち
- Given 直前の記事が未完読（complete_after_seconds 未満）When 次を完読 Then コンボは 1 から数え直す
- Given 記事に 3 行要約がある When ReadDone を開く Then 3 行がそのまま出る
- Given 要約が無い When ReadDone を開く Then 要約欄に「要約を準備中」が出て、画面はエラーにならない
- Given 今日 4 本目の完読 When ReadDone を開く Then 「今日のゴール 4 / 5 ・ あと 1 本で宝箱」
- Given 今日 5 本目の完読 When ReadDone を開く Then DailyGoal へ自動で進む（または宝箱ボタンが出る。未決 6）
- Given 未読が残っている When ReadDone を開く Then 「次の 1 本」に最も新しい未読が出る
- Given 未読が 0 When ReadDone を開く Then 「次の 1 本」の代わりに「全部読んだ」が出る
- Given 同じ記事を 2 回開いて戻った When 2 回目 Then XP は付かない（読了は 1 記事 1 回。冪等）

## 使う設定の鍵
dopamine.yml: `read.complete_after_seconds`, `xp.base`, `xp.combo_multiplier_step`, `xp.combo_max_multiplier`, `daily_goal.articles`, `claude.summary_model`
personas.yml: なし

## 外部 API
なし（要約は Unit 4 の `Claude::SummarizeArticleJob` が事前に付ける。失敗は `articles.summary_failed_at` / `summary_error`。画面は読むだけ）

## 未決
1. 推定読了時間の算出（本文文字数が要る。Unit 2 で本文列を持つか）
   → **Unit 2**: `articles.content`（readability の本文）を足した。文字数 ÷ 定数の定数は鍵が無い（提案: `read.chars_per_minute`）
   → **Unit 3b**: content は記事ページから readability で抜いた HTML（`ArticleContentFetcher`）。文字数は `Loofah.fragment(content).text` で数える。失敗した記事はフィードの抜粋のまま（`content_error` あり）
2. 完読の下限。モックは 60 秒、dopamine.yml は 20 秒。yml が正（変えるなら PR で提案）
3. 要約の金額「約 ¥0.3」を画面に出すか（出さない案。コストは Learning に集約）
4. 「ひとこと要約」の保存先（articles に列？ 別テーブル？）と +10 XP の鍵
   → **Unit 2**: `readings.note`（読了 1 行に 1 つ）。XP の鍵は無い（提案: `read.note_xp`）
5. 「記事から戻った」の検出方法（visibilitychange / pageshow / 記事を開く前にサーバーへ開始時刻を記録して戻り時に差分）。pwa-ios Skill を読んで決める
    → **決定（Unit 5、#35）**: 「読む」は Turbo を切った POST で `readings` に開始時刻（サーバー時計）を記録してから記事へ redirect。戻りは Stimulus `reading-return` が検出する。「読む」の submit で sessionStorage に印を付け、visibilitychange（standalone のアプリ内シートを閉じた）/ pageshow の bfcache 復元 / back_forward の再読込のいずれかで印があれば `POST /readings/return` を 1 回だけ送る。印を文書に持たないのは、戻り先が「読む」を押す前に描いた文書のままだから。取りこぼしは Main の白ピル「読了を記録」で手で送る。滞在は開始と戻りのサーバー時刻の差。ReadDone は full page（`GET /readings/:id`）。iPhone の standalone で visibilitychange が来るかは実機で確かめる（持ち越し）
    → **撤去（#43、ADR 0010）**: 戻りの検出（`reading-return`、Main の「読了を記録」ピル、`POST /readings/return`）は消した。判定はリーダーの末尾で行う。#40 は不要になった
6. 5 本目の読了で DailyGoal に自動遷移するか、ボタンを出すか
    → **Unit 5（#35）**: 第一の陣では文言「今日のゴール 5 / 5 ・ 読み切った！」だけ。遷移は DailyGoal を作る Unit 7 で決める
7. コンボの「連続」の定義。鍵が無い間は「同日内（reset_hour 基準）で完読が途切れない限り。未完読で途切れる」とする。時間窓（モックの「あと 2:14」）を入れるなら main.md 未決 3 の `xp.combo_window_seconds`
    → **決定（Unit 5、#35）**: 時間窓は持たない。同じ読書日の中で、戻った順に見て完読が途切れない本数 n に対し倍率 = min(1 + `xp.combo_multiplier_step` × n, `xp.combo_max_multiplier`)。未完で 0 に戻る。開いたまま戻っていない行は数えない。見出しの「N 本連続」は n + 1（この記事を含む）。同じ記事を未完のまま開き直して完読したときは、失敗した戻りは残らず（1 記事 1 行。ADR 0006）、途切れなかったものとして前の完読から続く。短い誤タップで鎖が切れないようにする意図。別の記事の未完は今までどおり途切れさせる
