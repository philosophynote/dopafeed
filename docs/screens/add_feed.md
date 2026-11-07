# AddFeed（Unit 16b、#77。自動検出は 16c、#81）

## 目的
購読の入口。フィードまたはサイトの URL、おすすめから追加する。登録は ADR 0015、自動検出は ADR 0017。

## 要素
1. シート（下から出る）: 「閉じる」（→ 開いた側の Main / Feeds）、「フィードを追加」、ボタン「追加」。Escape でも閉じられる
2. 「フィードまたはサイトの URL」入力（type=url、例 https://zenn.dev/feed）。標準の貼り付けを使う
3. 「おすすめ」6 件（固定）: Zenn トレンド zenn.dev/feed / Qiita 人気記事 qiita.com/popular-items/feed / はてブ テクノロジー b.hatena.ne.jp/hotentry/it.rss / Hacker News hnrss.org/frontpage / Publickey publickey1.jp/atom.xml / Swift.org Blog swift.org/atom.xml
4. 結果「『タイトル』を追加しました。記事を取得しています」。予約失敗なら「記事の取得は後ほど再試行します」。取り込み前の件数は表示しない
5. 注記「サイトの URL を入れても OK。ページ内の RSS/Atom リンクや /feed などの定番パスを自動で探します」

## 遷移
- Main の「+」/ Feeds の「+」→ AddFeed（Turbo Frame のシート）
- 「追加」→ 取得・解析・タイトル検証 → Feed を保存 → 取得 Job を積む → シートに結果。閉じると開いた側を再読み込み

## 受け入れ条件（Given-When-Then）
- Given RSS の URL When 追加 Then Feed が作られ、タイトルは RSS の title、取得 Job が積まれる
- Given サイトの URL（HTML / XHTML）When 追加 Then head の RSS/Atom リンクを文書順で最大 5 件、その後 /feed → /rss → /atom.xml → /index.xml を探索する。最初の有効なフィードの URL とタイトルで登録する
- Given リダイレクトされたサイト When 探索 Then 最終応答 URL を相対 href の基準、同じ origin のルートを定番パスの基準にする。base 要素は使わず、候補 HTML を再探索しない
- Given フィードが見つからないサイト When 追加 Then 「フィードが見つかりません」。一時的な通信失敗なら「フィードを確認できませんでした。時間をおいて試すか、RSS/Atom の URL を入力してください」。全体の時間切れなら「フィードの確認がタイムアウトしました。RSS/Atom の URL を入力してください」。登録・予約せず入力を残す
- Given 登録済みの URL When 追加 Then 重複せず「登録済み」と出る（feeds.url の unique）
- Given 取得に失敗する URL When 追加 Then Feed は作らず、エラーを表示
- Given 初回取得の予約が失敗 When 登録 Then Feed は残り、再試行を案内
- Given エラー When 再表示 Then 入力が残る。送信中は入力とおすすめからの追加を重ねて送れない
- Given Main / Feeds When 開閉 Then 開いた側に戻り、追加結果が反映される。390×844 で横スクロールなし、操作領域は 44px 以上

## 使う設定の鍵
dopamine.yml: `fetch.timeout_seconds`、`fetch.max_body_megabytes`（既存値を利用）
personas.yml: なし

## 外部 API
あり。RSS/HTML の取得（feedjira + Net::HTTP。テストは WebMock + spec/fixtures/files/feeds/*.xml。Unit 3 で VCR からこの方式に変えた。取得本体は `FeedFetcher`）

## 探索の境界
- 入口の取得から探索終了まで `fetch.timeout_seconds` を全体制限にも使う。個々の取得の宛先検査・リダイレクト上限・本文上限は既存 HttpGet を通す。同期再試行はしない。
- HTML 候補は `rel` のトークンに alternate、type が application/rss+xml / application/atom+xml のもの。属性値の大文字小文字と type のパラメータを吸収する。
- 空・不正・http(s) 以外・自身・重複 URL を除き、外部ホストも既存の宛先検査を通す。空タイトル・解析失敗・候補の取得失敗では次へ進む。
- 検出先が登録済みなら、その候補の再取得と予約をせず「登録済み」。サイト URL は保存しない。フィード自身の移転先への URL 更新は既存 FeedFetcher に任せる。
- 標準の貼り付けを使い、おすすめは固定文。HttpGet の残件は #62。
