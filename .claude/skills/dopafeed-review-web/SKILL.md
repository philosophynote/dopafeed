---
name: dopafeed-review-web
description: Dopafeed のレビューでルーティング、認証、コントローラー、ERB、Hotwire、Tailwind、iPhone PWA の操作を検査する。dopafeed-review からの委任、またはこれらの観点を指定したレビューで使う。
---

# 画面と HTTP のレビュー

1. `AGENTS.md`、`SECURITY.md`、関連する `docs/screens/` の受け入れ条件を読む。対象の版で `config/routes.rb` から認証・入力・永続化・レスポンス、画面の更新まで追う。[View の確認項目](references/view.md) と [Controller の確認項目](references/controller.md) を変更した経路に適用する。
2. `ApplicationController` と `Authentication` concern の適用範囲を確認する。一人用の構成でも、公開入口、セッション、CSRF、外部 URL・記事 HTML、レスポンスの境界は `SECURITY.md` とコードで照合する。
3. 画面変更では iPhone PWA の 390×844 で、操作から状態更新・表示までを確認する。関係する戻る操作、再読み込み、タップ、キーボード、動きを減らす設定、Turbo の再描画と Stimulus の再接続を確認する。画面の振る舞いは既存の system spec と照らす。
4. 指摘、確認事項、検証結果を `AGENTS.md` に従って日本語で返す。
