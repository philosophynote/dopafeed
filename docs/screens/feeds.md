# Feeds（Unit 未定・第二の陣。案: 16）

## 目的
購読の管理。フィードごとの件数・未読・最終更新・エラーを見せ、削除と手動更新ができる。

## 要素
1. 「購読 (4)」、ボタン「フィードを追加」（→ AddFeed）
2. フィード行 × N: タイトル、URL、「20件・未読 12」「更新 3分前」（DB: feeds + 集計）、取得失敗なら赤字「サーバーエラー (HTTP 503)」（DB: `feeds.last_fetched_at` / `feeds.last_error`。Unit 2 で足した）
3. 注記「左にスワイプで削除。下に引っ張ると全フィードをまとめて更新します。取得に失敗したフィードは赤字でエラーが出ます」（固定）
4. タブバー（購読が選択）

## 遷移
- タブバー「購読」→ Feeds（full page）
- 「+」→ AddFeed
- 左スワイプ → 削除（確認あり。記事も消すかは未決 1）
- 引っ張って更新 → 全フィードの取得 Job を積む（Turbo Stream で「更新 N 秒前」を差し替え）

## 受け入れ条件（Given-When-Then）
- Given フィードが 4 件 When Feeds を開く Then 4 行、各行に件数・未読・最終更新
- Given 最終取得が 503 When Feeds を開く Then その行に赤字で「サーバーエラー (HTTP 503)」
- Given 削除 When 確認 Then Feed と紐づく記事が消える（dependent: :destroy。未決 1）
- Given 引っ張って更新 When 離す Then 全フィードの取得 Job が積まれ、二重に積まれない

## 使う設定の鍵
dopamine.yml: 取得間隔は鍵が無い（未決 2）
personas.yml: なし

## 外部 API
なし（取得は Unit 3 の Job）

## 未決
1. フィード削除時に記事・読了記録・保存を消すか残すか
2. 定期取得の間隔（Solid Queue recurring）。提案: `fetch.interval_minutes: 30`
3. 「引っ張って更新」のジェスチャー実装（Stimulus。PWA の overscroll との兼ね合い）
