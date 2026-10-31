# AddFeed（Unit 未定・第二の陣。案: 16、Feeds と同 Unit）

## 目的
購読の入口。URL を貼るだけで RSS/Atom を見つけて追加する。おすすめ 6 件を置いて最初の一歩を短くする。

## 要素
1. シート（下から出る）: 「閉じる」（→ Main）、「フィードを追加」、ボタン「追加」
2. 「フィードまたはサイトの URL」入力（type=url、value 例 https://zenn.dev/feed）、ボタン「クリップボードから貼り付け」（未決 1）
3. 「おすすめ」6 件（固定）: Zenn トレンド zenn.dev/feed / Qiita 人気記事 qiita.com/popular-items/feed / はてブ テクノロジー b.hatena.ne.jp/hotentry/it.rss / Hacker News hnrss.org/frontpage / Publickey publickey1.jp/atom.xml / Swift.org Blog swift.org/atom.xml
4. 結果「『Zennのトレンド』を追加（20件）」（取得したタイトルと件数）
5. 注記「サイトの URL を入れても OK。ページ内の RSS/Atom リンクや /feed などの定番パスを自動で探します」（固定）

## 遷移
- Main の「+」/ Feeds の「+」→ AddFeed（Turbo Frame のシート）
- 「追加」→ Feed を作り、取得 Job を即時に積む → Feeds か Main に戻る（Turbo Stream で結果を差し込む）

## 受け入れ条件（Given-When-Then）
- Given RSS の URL When 追加 Then Feed が作られ、タイトルは RSS の title、取得 Job が積まれる
- Given サイトの URL（HTML）When 追加 Then `<link rel="alternate" type="application/rss+xml">` か定番パス（/feed, /rss, /atom.xml, /index.xml）から RSS を見つける。見つからなければ「フィードが見つかりません」
- Given 登録済みの URL When 追加 Then 重複せず「登録済み」と出る（feeds.url の unique）
- Given 取得に失敗する URL When 追加 Then Feed は作らず、エラーを表示（タイムアウトは未決 2）

## 使う設定の鍵
dopamine.yml: なし
personas.yml: なし

## 外部 API
あり。RSS/HTML の取得（feedjira + Net::HTTP。VCR: `feeds/zenn_feed.yml`, `feeds/site_autodiscovery.yml`, `feeds/not_found.yml`）

## 未決
1. 「クリップボードから貼り付け」は iOS Safari で navigator.clipboard.readText が許可を求める。無ければ入力だけ
2. 取得のタイムアウト（モックには無い。提案: `fetch.timeout_seconds: 10`）と再試行（Unit 3 の取得 Job と共通化）
3. おすすめ 6 件を yml に持つか固定文か（数字ではないので固定でよい）
