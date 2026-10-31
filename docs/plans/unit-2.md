# Unit 2「ドメインモデル」実行計画

状態: **承認済み 2026-10-31（nao）**

ブランチ: `unit-2-domain`（1 PR。migration 4 本 + モデル 4 つ + テスト。画面なし）

## Context
Unit 0 は seed のために feeds / articles の最小列だけを作り、「XP・既読・fetch 状態は Unit 2」と残した。
Unit 1 で 16 画面の「要素（出典: DB）」が出揃った。Unit 2 はそれを**列と関連**に落とし、
Unit 3（取得 Job）・4（要約 Job）・5〜7（Main / ReadDone / Roulette / Jackpot / DailyGoal）が
migration を書かずに実装へ入れる状態を作る。XP の計算・抽選・ストリークの**ロジックは書かない**（各 Unit が自分の受け入れ条件と一緒に書く）。
Unit 2 が持つのは「どこに何を保存するか」と、全 Unit が共有する**日付の境界**（reset_hour）だけ。

## 決めること（nao の承認で確定。ADR 0006 に書く）
1. **一人用なので user_id を持たない**。いいね・保存・読了は記事側に直接残す（ADR 0005「ユーザーは 1 人」の帰結）。多人数化するなら列を足す migration を書く
2. **読了は `readings` 1 記事 1 行（article_id unique）**。「読む」のタップで行を作り（opened_at + 抽選結果 tier）、戻ってきたら returned_at / completed_at / xp を埋める。
   同じ記事を二度開いても行は 1 つ → 「XP は 1 記事 1 回」「再抽選しない」（read_done / roulette / jackpot の冪等条件）が一意制約で守られる
3. **抽選はタップ時、結果は tier 名だけ保存**（main 未決 11 / roulette 未決 2 を「出目」で確定）。倍率・確率は常に yml から導く。確定した XP だけ `readings.xp` に数値で残す。
   → yml の倍率を後で変えても、過去の XP 合計は変わらず、表示の「×3」の類だけが新しい値になる
4. **いいねと保存は別の列**（`liked_at` / `bookmarked_at`。saved 未決 1）。表示は同じ「保存」に束ねる。学習への寄与の違いは第二の陣で使う
5. **日付の境界は `daily_goal.reset_hour`、タイムゾーンは Asia/Tokyo**。`config.time_zone = "Tokyo"` を Unit 2 で入れる（Unit 0 持ち越しの前倒し。理由: 境界の実装とテストがここにあるため）。
   Claude::Budget の「今日」は Tokyo の暦日になる（reset_hour は使わない。費用の日付と読書の日付は別のまま）
   補足（理解度チェックで食い違った点）: スナップショットするのは **tier 名と確定 xp の数値だけ**。倍率・確率は保存しない。
   yml の rare を ×3 → ×2 に変えると、過去の readings.xp と累計 XP は変わらないが、内訳に出す「×3」の表示は「×2」になる。「何も変わらない」ではない。
   表示まで固定したいなら tier_multiplier 列を足す別案になるが、「数字は yml にだけ置く」規約に反するので採らない
   補足 2: 開いたが complete_after_seconds 未満で戻った記事は **未読のまま Main に残る**（completed_at が nil なので unread）。
   次に「読む」を押しても readings は article_id 一意なので行は 1 つのまま、**前回の tier を使い回す**（再抽選しない）。再抽選する設計は採らない
6. **第二の陣の列は足さない**: Swipe の archived / 興味なし、Thompson の重み、Push 購読（Unit 10 で ADR）、Comments キャッシュ、ベクトル。持ち越しに列挙する

## 変更

### migration（db/migrate/、4 本）
- `add_fetch_state_to_feeds`: `last_fetched_at:datetime`, `last_error:string`（nil = 成功。Feeds 画面の赤字「サーバーエラー (HTTP 503)」はここ）, `etag:string`, `last_modified:string`（Unit 3 の条件付き GET）
- `add_content_and_reactions_to_articles`: `guid:string`（feedjira の entry_id。url と合わせた重複排除）, `content:text`（readability の本文。要約の入力と「約 N 分」の元。read_done 未決 1 / similar 未決 4）, `liked_at:datetime`, `bookmarked_at:datetime`。index: `[feed_id, guid]`, `liked_at`, `bookmarked_at`
- `create_readings`: `article:references(unique, fk)`, `opened_at:datetime null:false`, `returned_at:datetime`, `completed_at:datetime`, `tier:string null:false`, `combo_multiplier:decimal(3,1)`, `xp:integer null:false default 0`, `note:text`（ひとこと要約。read_done 未決 4）, timestamps。index: `completed_at`
- `create_daily_goals`: `day:date null:false unique`, `achieved_at:datetime`, `bonus_xp:integer null:false default 0`, timestamps

### モデル（app/models/）
- `Feed`: 変更なし（`has_many :articles, dependent: :destroy` のまま。記事経由で readings も消える）
- `Article`: `has_one :reading, dependent: :destroy`。scope `unread`（completed_at のある reading が無い。開いたが未完は未読のまま）, `read`, `saved`（liked_at か bookmarked_at）, `newest_first`（published_at desc, id desc）。`saved?`
- `Reading`（新規）: `belongs_to :article`。validates `opened_at` presence、`tier` inclusion in `Dopamine.tier_names`、`xp` ≥ 0、`article_id` uniqueness。`completed?`, `dwell_seconds`（returned_at − opened_at。未帰還なら nil）。scope `completed`, `on(day)`（ReadingDay の範囲で completed_at を絞る）
- `DailyGoal`（新規）: validates `day` presence / uniqueness。`achieved?`
- `ReadingDay`（新規 PORO、app/models/reading_day.rb）: `ReadingDay.of(time = Time.current) -> Date`（Time.zone に直し reset_hour 時間引いて to_date）, `ReadingDay.range(date) -> Range`（date の reset_hour 〜 翌日 reset_hour）。数字は yml から
- `Dopamine`（新規、lib/dopamine.rb。autoload_lib 済み）: `Dopamine.settings`（`config_for(:dopamine)` を 1 箇所に）, `Dopamine.tier_names`。Claude::Budget は触らない（既存の config_for 呼びは残す。差分を増やさない）

### 設定
- `config/application.rb`: `config.time_zone = "Tokyo"`
- `config/dopamine.yml`: 触らない

### テスト・fixtures（test/）
- `test/fixtures/readings.yml`: 完読 1 行（rails_81, tier rare, xp 入り）、開いただけ 1 行（weekly_770, tier common, completed_at nil）
- `test/fixtures/daily_goals.yml`: 達成 1 行
- `test/fixtures/articles.yml`: rails_82 に `liked_at`
- `test/models/reading_test.rb`: 必須列、tier は yml の名前だけ、article 一意、xp 負は不可、dwell_seconds、completed?、`on(day)` が境界で切れる
- `test/models/article_test.rb` に追加: unread（既読は出ない、開いただけは出る）、saved、newest_first、記事削除で reading も消える
- `test/models/daily_goal_test.rb`: day 一意、achieved?
- `test/models/reading_day_test.rb`: reset_hour の 1 分前は前日・ちょうどは当日（時刻は yml の reset_hour から組み立てる。4 を書かない）、range の両端、`Time.zone` が Tokyo
- `test/seeds_test.rb`: setup の delete_all に `Reading` / `DailyGoal` を足す（fixtures の readings が articles を参照しているので、先に消さないと FK で落ちる）
- 構造テスト: `xp`/`multiplier` に数値リテラルを書かない（migration の `default: 0` は db/ なので対象外。モデルには書かない）

### 文書
- `docs/decisions/0006-domain-model.md`: 上の「決めること」1〜5
- `docs/plans/unit-2.md`: この文書（承認済み印つき）
- `docs/screens/` の未決で確定したものに一行追記: main 未決 11 / roulette 未決 2（出目。Reading に保存）、read_done 未決 1・4（content 列 / readings.note）、saved 未決 1（別の列）、daily_goal 未決 5（Tokyo、Unit 2 で入れた）

## 手順（テスト先行）
1. `git checkout -b unit-2-domain`、docs/plans/unit-2.md
2. fixtures と model テストを書く → `bin/rails test test/models` が赤（テーブルが無い）
3. migration 4 本 → `bin/rails db:migrate`（schema.rb 更新）
4. モデル・ReadingDay・Dopamine を書いて緑
5. time_zone、seeds_test の修正、ADR 0006、screens 追記
6. `bin/ci` 緑 → reviewer → PR（テンプレート全欄。画面欄は「画面なし。system test 追加なし」）

## 差分の見込み
migration 70 + モデル 90 + fixtures 30 + テスト 200 ≈ 390 行（docs 別）。300 を少し超える。
テストが半分なので 1 PR で出す案。割るなら 2a（schema + モデル）/ 2b（ReadingDay + time_zone + ADR）だが、2b 単独は 50 行で薄いので勧めない。

## 触らないもの
`config/dopamine.yml`、`app/services/claude/`、seeds の内容（readings は seed しない）、`.kamal/secrets`、`config/master.key`、`.env*`

## 検証
- `bin/rails db:migrate` 後の schema.rb に readings / daily_goals と feeds / articles の新列
- `bin/rails test` 緑、`bin/rails test test/structure` 緑
- `bin/ci` が「Signoff: 緑」（system test は smoke のみで変化なし）
- `env RAILS_ENV=test bin/rails db:seed:replant` が通る（FK 順）

## 持ち越し（Unit 2 では足さない列）
- Swipe: `archived_at` / `dismissed_at`（興味なし）、一掃の鍵
- Learning / ForYou: フィード重み（Thompson の α/β）、タグ
- Install（Unit 10）: `push_subscriptions`（endpoint, p256dh, auth）。ADR と一緒に
- Comments: 記事ごとのコメントキャッシュ。Similar: ベクトル列（ADR 要）
- 推定読了時間の定数（提案: `read.chars_per_minute`）、ひとこと要約の XP（提案: `read.note_xp`）は PR 本文の提案欄へ
- Unit 4 が要約の失敗を記録したければ `summary_failed_at` をその Unit で足す
