# Feeds（Unit 16a・第二の陣、#72）

## 目的
購読の管理。フィードごとの件数・未読・最終取得・エラーを見せ、確認して削除できる。追加は 16b（#77）、手動更新は #22 完了後の別 Unit。

## 要素
1. 「購読 (4)」、ボタン「フィードを追加」（16b までは無効）
2. フィード行 × N: タイトル、URL、「20件・未読 12」「最終取得 3分前」（DB: feeds + 集計）、取得失敗なら赤字「サーバーエラー (HTTP 503)」（DB: `feeds.last_fetched_at` は成否を問わない試行時刻、`feeds.last_error` が nil なら成功）
3. 注記「左にスワイプ、または削除ボタンで削除します。取得に失敗したフィードは赤字でエラーが出ます」（固定）
4. タブバー（購読が選択）

## 遷移
- タブバー「購読」→ Feeds（full page）
- 左スワイプ / 削除ボタン → 影響を確認 → 削除して Feeds に戻る。確認キャンセルでは残る
- AddFeed は 16b、引っ張って更新は #22 完了後

## 受け入れ条件（Given-When-Then）
- Given フィードが 4 件 When Feeds を開く Then 4 行、各行に件数・未読・最終取得
- Given 最終取得が 503 When Feeds を開く Then その行に赤字で「サーバーエラー (HTTP 503)」
- Given 削除 When 確認 Then Feed と記事・いいね・保存・読了が消え、別フィードと達成済み DailyGoal は残る（ADR 0014）。確認文に累計 XP・読了数・連続日数への影響を明記する
- Given 削除確認 When キャンセル Then フィードは残る
- Given 未取得 / 記事 0 件 / 購読 0 件 When 開く Then 「未取得」/「0件・未読 0」/「購読中のフィードはありません」
- Given 右・縦・短いスワイプ / 中断 When 離す Then 削除しない。390×844 で横スクロールがなく、タップ領域は 44px 以上

## 使う設定の鍵
dopamine.yml: 取得間隔は鍵が無い（未決 2）
personas.yml: なし

## 外部 API
なし（取得は Unit 3 の Job）

## 未決
1. 削除範囲 → #72 で承認。ADR 0014 のとおり記事・読了・保存も削除
2. 定期取得の間隔（Solid Queue recurring）。提案: `fetch.interval_minutes: 30` → Unit 3 で確定: 間隔は Solid Queue が読む config/recurring.yml にだけ置く（`every 30 minutes`）。dopamine.yml には持たない（二重に持つと食い違う）
3. 「引っ張って更新」のジェスチャー実装（Stimulus。PWA の overscroll との兼ね合い）
