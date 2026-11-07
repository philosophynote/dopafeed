# ADR 0006: ドメインモデルは一人用。読了は 1 記事 1 行、日付は reset_hour で切る
日付: 2026-10-31 状態: 採用（Unit 2 で実装）

1. **user_id を持たない。** ADR 0005「ユーザーは 1 人」の帰結として、いいね（`articles.liked_at`）・保存（`articles.bookmarked_at`）・読了（`readings`）は記事側に直接残す。多人数化するときは列を足す migration を書く
2. **読了は `readings` 1 記事 1 行（article_id unique）。**「読む」のタップで行を作り（`opened_at` + 抽選結果 `tier`）、戻ってきたら `returned_at` / `completed_at` / `xp` を埋める。同じ記事を二度開いても行は 1 つなので、「XP は 1 記事 1 回」「再抽選しない」が一意制約で守られる。開いたが `read.complete_after_seconds` 未満で戻った記事は `completed_at` が nil のまま未読に残り、次に「読む」を押しても前回の tier を使い回す
3. **抽選はタップ時、保存するのは tier 名と確定した xp の数値だけ。** 倍率・確率はスナップショットせず常に config/dopamine.yml から導く。yml の倍率を後で変えても過去の累計 XP は変わらないが、内訳に出す「×3」のような倍率表示は新しい値になる。表示まで固定したいなら列を足す別案になるが「数字は yml にだけ置く」規約に反するので採らない
4. **いいねと保存は別の列。** 表示は同じ「保存」に束ねる（`Article.saved`）。学習への寄与の違いは第二の陣で使う
5. **読書の日付は `daily_goal.reset_hour`、タイムゾーンは Asia/Tokyo（`config.time_zone = "Tokyo"`）。**`ReadingDay.of(time)` / `ReadingDay.range(date)` が唯一の境界計算。Claude::Budget の「今日」は費用の日付なので reset_hour を使わず Time.zone の暦日のまま（UTC から Tokyo の暦日に変わった）
6. **XP の計算・抽選・コンボ・ストリークのロジックは Unit 2 に置かない。** 各画面の Unit（5〜7）が受け入れ条件と一緒に書く。Unit 2 は「どこに何を保存するか」と日付の境界だけ

第二の陣の列（Swipe の archived / 興味なし、Thompson の重み、Push 購読、Comments キャッシュ、ベクトル）は足さない。それぞれの Unit で ADR と一緒に。
