# AddFeed（Unit 16b、#77。サイト URL の自動検出は 16c、#81）

## 目的
購読の入口。RSS/Atom の URL またはおすすめから追加する。サイト URL の自動検出は #81。登録の流れは ADR 0015。

## 要素
1. シート（下から出る）: 「閉じる」（→ 開いた側の Main / Feeds）、「フィードを追加」、ボタン「追加」。Escape でも閉じられる
2. 「フィードの URL」入力（type=url、例 https://zenn.dev/feed）。標準の貼り付けを使う
3. 「おすすめ」6 件（固定）: Zenn トレンド zenn.dev/feed / Qiita 人気記事 qiita.com/popular-items/feed / はてブ テクノロジー b.hatena.ne.jp/hotentry/it.rss / Hacker News hnrss.org/frontpage / Publickey publickey1.jp/atom.xml / Swift.org Blog swift.org/atom.xml
4. 結果「『タイトル』を追加しました。記事を取得しています」。予約失敗なら「記事の取得は後ほど再試行します」。取り込み前の件数は表示しない
5. 注記「RSS/Atom の URL を入力してください。サイト URL の自動検出は準備中です」

## 遷移
- Main の「+」/ Feeds の「+」→ AddFeed（Turbo Frame のシート）
- 「追加」→ 取得・解析・タイトル検証 → Feed を保存 → 取得 Job を積む → シートに結果。閉じると開いた側を再読み込み

## 受け入れ条件（Given-When-Then）
- Given RSS の URL When 追加 Then Feed が作られ、タイトルは RSS の title、取得 Job が積まれる
- Given サイトの URL（HTML）When 追加 Then 「RSS/Atom の URL を入力してください」。自動検出は #81 でリンクと定番パスを探索する
- Given 登録済みの URL When 追加 Then 重複せず「登録済み」と出る（feeds.url の unique）
- Given 取得に失敗する URL When 追加 Then Feed は作らず、エラーを表示（タイムアウトは未決 2）
- Given 初回取得の予約が失敗 When 登録 Then Feed は残り、再試行を案内
- Given エラー When 再表示 Then 入力が残る。送信中は入力とおすすめからの追加を重ねて送れない
- Given Main / Feeds When 開閉 Then 開いた側に戻り、追加結果が反映される。390×844 で横スクロールなし、操作領域は 44px 以上

## 使う設定の鍵
dopamine.yml: `fetch.timeout_seconds`、`fetch.max_body_megabytes`（既存値を利用）
personas.yml: なし

## 外部 API
あり。RSS/HTML の取得（feedjira + Net::HTTP。テストは WebMock + spec/fixtures/files/feeds/*.xml。Unit 3 で VCR からこの方式に変えた。取得本体は `FeedFetcher`）

## 未決
1. 「クリップボードから貼り付け」は iOS Safari で navigator.clipboard.readText が許可を求める。無ければ入力だけ
2. 取得のタイムアウト（モックには無い。提案: `fetch.timeout_seconds: 10`）と再試行（Unit 3 の取得 Job と共通化）。→ **Unit 3b**: `fetch.timeout_seconds: 10` を dopamine.yml に入れた（nao 承認、PR #26）。`HttpGet` が接続・読み取りの両方に使う。再試行は 408・429・5xx・接続エラーだけ Job の retry_on（既定の回数・間隔）
3. おすすめ 6 件を yml に持つか固定文か（数字ではないので固定でよい）
4. URL 入力を受けるときの守り（Unit 3 の reviewer 指摘）: `FeedFetcher` は scheme を http(s) に限るだけで、ループバック・リンクローカルへのリダイレクトと本文サイズの上限は持たない。一人用で登録者が nao だけの間は刺さらないが、この画面を作る Unit で入れる。→ **#23**: `HttpGet` に入れた（内部アドレスは拒否リスト、DNS を先に解いてその IP に接続、本文は `fetch.max_body_megabytes: 5` で切る。nao 承認）
