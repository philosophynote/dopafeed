# Weekly（Unit 34、#173。34a 集計 → 34b Claude のひとこと → 34c 画像で共有）

## 目的
社会的報酬の「過去の自分と比べる」版。週の読了数・時間・手に入れたカード・フィード別内訳と Claude のひとことを 1 枚のカードにして画像で共有できる。

## 要素
1. ヘッダ: 「‹ 図鑑へ戻る」（34a）。ボタン「画像で共有」は 34c（未決 1）
2. セグメント「今週 / Garden」は出さない（Garden は段 4。今週だけを見せ、前の週へ送る操作は持ち越し）
3. カード: 「今週のレポート」「11/16 – 11/22」「🔥 7 日連続」（`ReadingStreak.days`）、「32 本 読了」「先週比 +39%（23 本）」（先週 0 本なら比は出さず「先週 0 本」）、曜日別の棒 7 本（月〜日。一番多い日を最大の高さにし、0 本の日は棒なし。今日の曜日は橙の字、まだ来ない日は薄い灰の字。`data-day-state` が today / future / past）
4. 「読書時間 2時間41分」（今週完読した行の滞在の合計。未完の行は数えない。開いたまま放置した記事で膨らむのは #41 で直す）「カード 23 枚」と内訳「ノーマル a ・ レア b ・ S レア c ・ SS レア d」（判定中があれば「・ 判定中 e」。図鑑と同じ書き方。ADR 0020。モックの「獲得 XP」は出さない）「ひとこと要約 11 本」（今週完読した記事のうち要約のある本数）
5. フィード別「Zenn 14 / Publickey 9 / はてブ 6 …」本数の多い順に全部、同数はフィード名順（上位 N と「その他」にまとめるには本数の鍵が要るので畳まない）。0 本の週は節ごと出さない
6. 「Claude のひとこと ・ 11/9 – 11/15 の週」（34b）: 終わった週（先週）について Claude が書いた 2〜3 文（120 字以内）。例「Solid Queue と Turbo Streams、Rails の裏側を続けて読んだ週でした。…来週は障害報告をもう 1 本読み、運用の目線も足してみましょう。」（DB: `weekly_comments`。先週分が無い・失敗した週は欄ごと出さない）
7. フッター「DopaFeed ・ 過去の自分と比べる週次カード」、タブバー（「図鑑」が現在地。レポートの枠は無い）

## 遷移
- 図鑑の内訳の下の 1 行「今週 N 本 ・ 先週比 +X% ›」→ Weekly（full page、`GET /weekly`）。タブは足さず、Weekly でもタブバーは「図鑑」が現在地
- 「図鑑へ戻る」→ Collection
- 「画像で共有」→ 画像生成（未決 1）→ iOS の共有シート

## 受け入れ条件（Given-When-Then）
- Given 今週 32 本、先週 23 本 When Weekly を開く Then 「32 本」「先週比 +39%」（小数点以下は四捨五入。モックの +40% は丸めの違い）
- Given 週次 Job が走った When Weekly を開く Then Claude のひとことが出て、同じ週に再生成しない
- Given 前の週の完読が 0 本 When 週次 Job が走る Then Claude を呼ばず、ひとことの欄は出ない
- Given Claude の応答が形式不正 When 週次 Job が走る Then 失敗を 1 行に残し、その週は呼び直さず、欄は出ない
- Given 今週の読了 0 When Weekly を開く Then 0 本で画面が崩れない（棒グラフは空）
- Given 先週 0 本 When Weekly を開く Then 先週比は出さず「先週 0 本」
- Given 月曜の reset_hour の 1 分前に完読 When Weekly を開く Then 前の週に数える
- Given 図鑑 When 内訳の下の 1 行を押す Then Weekly が開き、タブバーは「図鑑」が現在地
- Given 390×844 When Weekly を開く Then 横スクロールが無く、タップ領域は 44px 以上

## 使う設定の鍵
dopamine.yml: `claude.curation_model`（週次コメントのモデル）、`claude.weekly_comment_max_tokens`（提案中。無い間は `claude.summary_max_tokens`）
personas.yml: なし

## 外部 API
あり。Claude（`Claude::WeeklyCommentJob` → `Claude::WeeklyCommenter`、VCR: `claude/weekly_comment/ok.yml`）。`config/recurring.yml` で毎時積み、月曜の reset_hour を過ぎて前の週の行が無いときだけ 1 回呼ぶ（成功も失敗も 1 週 1 行。行のある週は呼び直さない）。前の週の完読が 0 本なら呼ばない。送るのは完読した記事の見出し・フィード名・段と本数だけ（本文・URL は送らない）

## 未決
1. 画像生成の方法（サーバーで HTML → PNG は重い。Canvas で描くか、html-to-image 系は外部 JS なので不可。OG 画像的にサーバー側で SVG → PNG？ ADR が要る）
2. ~~週の始まり（モックは金曜始まり 10/3–10/9）~~ → **決定（#173）**: 月曜始まり、境は `daily_goal.reset_hour`（月曜 4:00 から翌月曜 4:00 の手前まで）
3. ~~週次コメントのモデルと、ひとことの文字数上限~~ → **決定（#173）**: モデルは `claude.curation_model`（ADR 0002）、長さはプロンプトで 2〜3 文・120 字以内
