# ADR 0016: 記事の画像は og:image を直リンクで出す
日付: 2026-11-07 状態: 採用（#87 の計画を nao が承認）

- 画像の URL は本文取得（`ArticleContentFetcher`）が同じ HTML から拾う（`og:image`、無ければ `twitter:image`）。追加の HTTP は無い。フィードの `media:thumbnail` は Feedjira の前処理（#27）で取れないので使わない。
- `articles.image_url` には https の絶対 URL だけ残す（http は https のページで混在コンテンツ、`data:` などは置かない）。
- 画像は自サーバーで中継・縮小せず、端末が配信元から直に読む（`referrerpolicy="no-referrer"`、`loading="lazy"`）。中継は libvips・キャッシュの置き場・縮小の CPU とメモリを 1GB の箱に載せ、HttpGet を画像にも通す面が増える。一人用には重い。
- 失うもの: 画像の CDN に端末の IP が見える（記事を開けば同じサイトに行くので小さい）。画像の大きさは配信元まかせ。気になれば中継を別に起こす。
