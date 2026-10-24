# 冪等。bin/setup と CI の「Tests: Seeds」段（db:seed:replant）で毎回流れる。
# 本番でも db:prepare が DB を新規作成した初回に一度流れる（User だけ。下の return を見よ）。
# 乱数・Time.current は使わない（二度流しても同じ結果、テストで件数を固定できる）。
# 記事 URL は example.com。seed のために実サイトへ偽パスを向けない。

# --- User（ADR 0005: 1 人用。seed で 1 件）----------------------------------
# development / test は既定値で通す（CI と bin/setup を secrets 無しで回すため）。
# production は ENV 必須。既定パスワードのユーザーを本番に作らないため、無ければ KeyError で止まる。
credential = lambda do |key, default|
  Rails.env.production? ? ENV.fetch(key) : ENV.fetch(key, default)
end

email_address = credential.call("DOPAFEED_USER_EMAIL", "nao@example.com")
password = credential.call("DOPAFEED_USER_PASSWORD", "password")

# 既存ユーザーのパスワードは上書きしない（再 seed で本番のパスワードを戻さない）
if User.none?
  User.create!(email_address: email_address, password: password)
end

# --- Feeds / Articles ----------------------------------------------------------
# 開発・テスト用のダミー。本番には入れない（本番のフィードは画面から登録し、記事は Unit 3 の取得 Job が作る）
return if Rails.env.production?

feeds = [
  { slug: "rails", title: "Ruby on Rails Blog", url: "https://rubyonrails.org/blog/feed.xml", site_url: "https://rubyonrails.org/blog" },
  { slug: "rubyweekly", title: "Ruby Weekly", url: "https://cprss.s3.amazonaws.com/rubyweekly.com.xml", site_url: "https://rubyweekly.com" },
  { slug: "martians", title: "Evil Martians Chronicles", url: "https://evilmartians.com/chronicles.atom", site_url: "https://evilmartians.com/chronicles" },
  { slug: "thoughtbot", title: "thoughtbot Blog", url: "https://thoughtbot.com/blog.rss", site_url: "https://thoughtbot.com/blog" },
  { slug: "shopify", title: "Shopify Engineering", url: "https://shopify.engineering/blog.atom", site_url: "https://shopify.engineering" }
]

# 各フィード 6 本。[title, 3 行要約]
articles = {
  "rails" => [
    [ "Rails 8.1 の新機能まとめ", "・bin/ci と config/ci.rb で CI の段をコードにする\n・Active Job Continuations で長いジョブを途中から再開\n・構造化イベントで本番ログを機械が読める形に" ],
    [ "Solid Queue を本番で運用して分かったこと", "・SQLite でも 1 プロセスで数千ジョブ/時は余裕\n・polling_interval は 1 秒で十分\n・失敗ジョブは FailedExecution を見るのが早い" ],
    [ "Propshaft に移行する手順", "・Sprockets の manifest を消すところから\n・digest 付きパスは asset_path で解決\n・Tailwind は tailwindcss-rails が builds/ に吐く" ],
    [ "Kamal 2 で一台運用", "・kamal-proxy が TLS と zero-downtime を担う\n・accessory で DB を同居させられる\n・secrets は .kamal/secrets に集約" ],
    [ "Hotwire で画面を速くする 5 つの型", "・Turbo Frame で部分置換\n・Stream で一覧の先頭に差し込む\n・Stimulus は小さく保つ" ],
    [ "SQLite が本番で使える理由", "・WAL と busy_timeout で書き込みの競合を吸収\n・1 台構成なら最速の選択\n・Litestream でバックアップを継続" ]
  ],
  "rubyweekly" => [
    [ "Ruby Weekly 770: Ruby 4.0 の変更点", "・Prism が既定のパーサになった\n・YJIT が既定で有効\n・Set が組み込みクラスに" ],
    [ "Ruby Weekly 771: 並行処理の今", "・Ractor の実用例が増えてきた\n・Fiber Scheduler と Async の組み合わせ\n・Thread の GVL を測る道具" ],
    [ "Ruby Weekly 772: 型と LSP", "・RBS の推論が賢くなった\n・ruby-lsp が Rails を理解する\n・Steep と Sorbet の使い分け" ],
    [ "Ruby Weekly 773: テストの速度", "・並列テストの worker 数の決め方\n・fixtures と factory の損益分岐\n・system test は少なく厚く" ],
    [ "Ruby Weekly 774: gem の作法", "・Gemfile.lock を gem に含めない\n・CI で複数 Ruby を回す\n・CHANGELOG は Keep a Changelog 形式" ],
    [ "Ruby Weekly 775: 小さな便利メソッド", "・Array#sum と Enumerable#tally\n・Hash#except と #slice\n・Data.define で値オブジェクト" ]
  ],
  "martians" => [
    [ "AnyCable で WebSocket を安く", "・Go 製サーバーが接続を持つ\n・Rails は RPC で論理だけ\n・1 GB のサーバーでも数千接続" ],
    [ "Rails アプリの N+1 を根絶する", "・strict_loading を全体で有効化\n・includes と preload の違い\n・ログで検知して CI で落とす" ],
    [ "フロントエンドを捨てて Hotwire に戻った話", "・SPA のビルドが重荷だった\n・Turbo で体感は変わらなかった\n・チームの速度は倍になった" ],
    [ "PostgreSQL から SQLite へ", "・一人用サービスには十分\n・バックアップは Litestream\n・移行は 1 日で終わった" ],
    [ "Docker イメージを 200MB 以下にする", "・multi-stage build で build 依存を捨てる\n・jemalloc でメモリを減らす\n・bootsnap precompile を忘れない" ],
    [ "Stimulus の設計原則", "・コントローラは 1 画面要素に 1 つ\n・状態は data 属性に置く\n・値の型は Values API で宣言" ]
  ],
  "thoughtbot" => [
    [ "テストを先に書く本当の理由", "・設計の粗が先に見える\n・赤を見てから緑にする\n・リファクタの安全網になる" ],
    [ "Rails のサービスオブジェクトは要るか", "・モデルに置けるならモデルに\n・外部 API を包むときだけ作る\n・入出力は PORO にする" ],
    [ "PWA を iPhone で動かすときの落とし穴", "・ホーム画面追加でしか Push が来ない\n・振動 API は無い\n・バッジは Badging API で" ],
    [ "コードレビューの型", "・差分の意図を先に読む\n・テストが無い分岐を探す\n・褒めるより具体的に指摘" ],
    [ "ActiveJob の再試行戦略", "・retry_on は指数バックオフで\n・discard_on は業務上の無効を表す\n・冪等でないジョブは再試行しない" ],
    [ "Tailwind をチームで使う規約", "・ユーティリティは並び順を固定\n・コンポーネントは partial に\n・@apply は最小限" ]
  ],
  "shopify" => [
    [ "YJIT が本番で 20% 速くした話", "・メモリは 10% 増えた\n・ウォームアップは数分\n・Ruby 3.3 以降なら迷わず有効化" ],
    [ "巨大モノリスを分割せずに保つ", "・パッケージ境界を packwerk で守る\n・循環依存を CI で落とす\n・チームごとの所有を明示" ],
    [ "Ruby の型を本番に入れる", "・Sorbet を段階的に導入\n・RBI は自動生成\n・型エラーを CI で止める" ],
    [ "Rails でのフィーチャーフラグ", "・フラグは DB で管理\n・古いフラグを消す期限を持つ\n・テストは両方の分岐を回す" ],
    [ "Liquid テンプレートの安全性", "・ユーザー入力をコードとして実行しない\n・リソース上限を設ける\n・サンドボックスの穴は監査する" ],
    [ "ジョブキューを 1 日 10 億件さばく", "・キューの分離が肝\n・失敗の可視化を先に作る\n・ワーカーの自動スケール" ]
  ]
}

base_time = Time.utc(2026, 10, 1, 9)

feeds.each_with_index do |attrs, feed_index|
  feed = Feed.find_or_create_by!(url: attrs[:url]) do |f|
    f.title = attrs[:title]
    f.site_url = attrs[:site_url]
  end

  articles.fetch(attrs[:slug]).each_with_index do |(title, summary), article_index|
    Article.find_or_create_by!(url: "https://example.com/#{attrs[:slug]}/#{article_index + 1}") do |a|
      a.feed = feed
      a.title = title
      a.summary = summary
      a.published_at = base_time + article_index.days + feed_index.hours
    end
  end
end
