# ADR 0017: サイトからのフィード探索は順番と通信範囲を限定する
日付: 2026-11-08 状態: 採用（#81 の計画を nao がチャットで承認、日本時間）

- FeedDiscovery が HttpGet と既存 FeedDocument で URL と非空タイトルを検証する。保存と初回取得の予約は FeedRegistration の責務とし、ADR 0015 を継続する。
- 入口はまず RSS/Atom として解析する。解析できず Content-Type が text/html / application/xhtml+xml の場合だけ、HTML の head の alternate リンク（application/rss+xml / application/atom+xml）を文書順で試す。
- 相対 href は一時移動も含む最終応答 URL（HttpGet の final_url）で解決する。permanent_url は恒久移転の記録として維持する。base 要素は使わない。
- HTML 候補は有効・重複除去後の先頭 5 件まで。その後、最終応答の origin の /feed → /rss → /atom.xml → /index.xml。自身と取得済み候補を重ねず、候補の HTML は再探索しない。最初の有効なフィードで止める。
- 候補数は HttpGet::MAX_REDIRECTS と同じく外部通信を制限する技術定数。報酬の調整値ではなく、config/dopamine.yml は変更しない。さらに既存 fetch.timeout_seconds を入口から探索完了までの全体制限に使い、HttpGet の接続エラーとは別の例外で打ち切る。
- http(s) の外部ホストも候補にできるが、全取得・リダイレクトで既存の宛先検査と本文上限を通す。既知の残件は #62。同期再試行はしない。
- 検出した候補 URL を保存する。候補の取得前に登録済みなら再取得・予約せず終了する。フィード自身のリダイレクト別名は統合せず、恒久移転の更新は既存 FeedFetcher に任せる。
- 入口の取得・直接フィードの検証失敗は既存エラー。候補の拒否・取得失敗・解析失敗・空タイトルは次へ進む。全候補で見つからなければ未検出、一時的な通信失敗があれば確認不能、全体制限なら時間切れとして案内する。保存と予約は行わず、入力を残す。

## 境界
5 件より後の HTML 候補、base 要素、再帰巡回、サブディレクトリの定番パス、HTML の Content-Type を示さないページ、複数フィードの選択は対象外。遅いサイトでは後半候補を試す前に全体制限に達する。上限や待ち時間を変えるときは別途提案する。
