# docs/screens 索引

画面モック: https://claude.ai/artifact/UF3JSQDBeEUGhESB3JvWyx（22 artboard + 設計メモ 8 枚）。Unit 1 で写し取った。
各ファイルは _TEMPLATE.md の見出しを持つ。実装する Unit は、着手前に「受け入れ条件」をテストに写し、「未決」を nao に聞く。

| 段 | 画面 | ファイル | モックの artboard | Unit | 深さ |
|---|---|---|---|---|---|
| 1 コアループ | Main | main.md | Main.dc.html | 5 | 深 |
| 1 | Swipe | swipe.md | Swipe.dc.html | 未定（案: 8） | 浅 |
| 1 | Roulette | roulette.md | Roulette.dc.html | 6 | 深 |
| 1 | Jackpot | jackpot.md | Jackpot.dc.html | 6 | 深 |
| 1 | ReadDone | read_done.md | ReadDone.dc.html | 5 | 深 |
| 1 | DailyGoal | daily_goal.md | DailyGoal.dc.html | 7 | 深 |
| 1 | Comments | comments.md | Comments.dc.html | 未定（案: 9） | 浅 |
| 2 個人最適化 | ForYou | for_you.md | ForYou.dc.html | 未定（案: 11） | 浅 |
| 2 | Learning | learning.md | Learning.dc.html | 未定（案: 12） | 浅 |
| 2 | Weekly | weekly.md | Weekly.dc.html | 未定（案: 13） | 浅 |
| 2 | Install | install.md | Install.dc.html | 10 | 深 |
| 2 | Similar | similar.md | Similar.dc.html | 未定（案: 14） | 浅 |
| 3 管理 | AddFeed | add_feed.md | AddFeed.dc.html | 未定（案: 16、Feeds と同 Unit） | 浅 |
| 3 | Saved | saved.md | Saved.dc.html | 未定（案: 17） | 浅 |
| 3 | Feeds | feeds.md | Feeds.dc.html | 未定（案: 16） | 浅 |
| 3 | Login | login.md | Login.dc.html | 15 | 深 |
| 4 アウトプット | NetaBox | （書かない） | NetaBox.dc.html | 第一の陣の対象外 | - |
| 4 | Quest | （書かない） | Quest.dc.html | 同上 | - |
| 4 | Garden | （書かない） | Garden.dc.html | 同上 | - |
| 4 | Gacha | （書かない） | Gacha.dc.html | 同上 | - |
| 4 | Hypothesis | （書かない） | Hypothesis.dc.html | 同上 | - |
| 4 | Suggest | （書かない） | Suggest.dc.html | 同上 | - |

- 「深」= 受け入れ条件を Given-When-Then で網羅（第一の陣で実装する 7 枚）。「浅」= 目的・要素・遷移・未決を埋め、受け入れ条件は主要なものだけ。実装する Unit の直前に見直す
- Unit 番号の「案」は milestone-1 の 10 個（0〜7, 10, 15）の隙間を SPEC の段の順に埋めたもの。nao が決める
- 第一の陣の導線: Main の設定ボタンから Learning の最小版（サインアウト + Install への導線だけ。Unit 5 で置く）→ Install（Unit 10）。AddFeed / Feeds は第二の陣で、第一の陣の 5 フィードは seed と Unit 3 の取得 Job で入れる（main.md / install.md / login.md / learning.md 未決 4 はこの前提）
- 段 4 は「本丸を一週間使ってから決める」（milestone-1）。読む側（興奮）と書く側（静か）でトーンを分け、書く側にルーレットは出さない（設計メモ split）

## モック共通の見た目（全画面）
- 390×844、角丸 48、背景 #F2F2F7、文字 #141416、アクセント #FF2E6B（props で #F0831A / #7C3AED / #0A84FF に切替可）
- 上の余白 56px（ステータスバー）。下タブバーは高さ 83px、4 タブ: フィード（未読バッジ）/ 保存 / レポート / 購読
- タップ領域は 44px 以上。アイコンは inline SVG（絵文字なし）
- カードは白、角丸 20、padding 14。見出し 18px/700、本文 13px、メタ 12px
