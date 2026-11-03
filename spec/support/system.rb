# iPhone の PWA が主戦場なので、システムテストは全部 390×844 の headless Chrome で回す。
# 例が終わるごとに tmp/screenshots/<spec 名>_<例の説明>.png を 1 枚残す（bin/screens が集めて PR に貼る）。
module SystemScreen
  # CSS ピクセルでの画面サイズ（幅, 高さ）
  SCREEN_SIZE = [ 390, 844 ].freeze
  # スクショの保存先
  SCREENSHOT_DIR = Rails.root.join("tmp/screenshots")
  # chromedriver からの応答を待つ上限（秒）。Selenium の既定は 120 秒で、ブラウザが応答しなくなると
  # 残りの例と after（スクショ・reset）の 1 操作ごとにこれだけ待ち、CI が数十分になる。
  # 正常な操作は Chrome の起動を含めても数秒なので、短くして失敗の報告まで早く着かせる
  DRIVER_READ_TIMEOUT_SECONDS = 20
  # chromedriver のログ（命令と応答）。ブラウザが応答しなくなったとき、どの命令で止まったかを
  # 失敗した例の後にジョブのログへ出す（#38。CI の artifact は箱から開けないので標準エラーで読む）
  CHROMEDRIVER_LOG = Rails.root.join("log/chromedriver.log")
  # Chrome が裏で落としてきて動かす機械学習モデル（言語判定・フィッシング判定・最適化ガイド）を止める。
  # CI の Google Chrome は「読む」の click の直後に TensorFlow Lite のモデルを動かし始め、そのまま描画プロセスが
  # 応答しなくなった（click が返らず、POST もサーバーに届かない。#38 の無応答も同じ形）。Playwright と Puppeteer が
  # 既定で付けている止め方に揃える。テストは画面の振る舞いを見るので、これらの機能は要らない
  QUIET_CHROME_ARGS = %w[
    --disable-background-networking
    --disable-component-update
    --disable-client-side-phishing-detection
    --disable-field-trial-config
    --disable-features=Translate,OptimizationHints,OptimizationGuideModelDownloading,OptimizationHintsFetching,OptimizationTargetPrediction
  ].freeze
  # iPhone Safari の UA。standalone 判定などで iOS 向けの分岐を踏ませる
  IPHONE_USER_AGENT = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1".freeze

  # 今の画面を screenshot_path に保存する。
  #
  # @param suffix [String, nil] 同じ例の中で複数枚撮るときの区別
  # @return [Pathname] 保存したファイル
  def screenshot!(suffix = nil)
    SCREENSHOT_DIR.mkpath
    path = screenshot_path(suffix)
    page.save_screenshot(path.to_s)
    path
  end

  # 今の例のスクショの保存先。tmp/screenshots/<spec 名>_<例の説明>[_suffix].png
  #
  # @param suffix [String, nil] 同じ例の中で複数枚撮るときの区別
  # @return [Pathname]
  def screenshot_path(suffix = nil)
    SCREENSHOT_DIR.join("#{screenshot_name(suffix)}.png")
  end

  # CSS が見ている viewport 幅（layout viewport = documentElement.clientWidth）。端末エミュレーションが効けば SCREEN_SIZE の幅。
  # window.innerWidth は使わない: GitHub Actions の headless Chrome では最初のページで innerWidth だけが 609（= 390 × 1.5625）
  # を返し、clientWidth・screen.width・ウィンドウ寸法は 390 のままだった（2 例目からは 390）。メディアクエリが使うのは layout viewport
  # Capybara の既定待ち時間だけ期待幅になるのを待ち、待っても違えば最後に読めた値を返す（失敗文に出す）
  #
  # @return [Integer]
  def viewport_width
    page.document.synchronize do
      width = page.evaluate_script("document.documentElement.clientWidth")
      raise Capybara::ElementNotFound, "viewport #{width}px" unless width == SCREEN_SIZE[0]

      width
    end
  rescue Capybara::ElementNotFound
    page.evaluate_script("document.documentElement.clientWidth")
  end

  # メディアクエリが SCREEN_SIZE の幅を見ているか（Tailwind のブレークポイントが使う値）
  #
  # @return [Boolean]
  def media_query_sees_screen_width?
    page.evaluate_script("window.matchMedia('(width: #{SCREEN_SIZE[0]}px)').matches")
  end

  # 失敗したときに切り分けに使う情報（ウィンドウ寸法・viewport の各値・UA）
  #
  # @return [String]
  def viewport_diagnostics
    window = page.driver.browser.manage.window.size
    metrics = page.evaluate_script(<<~JS)
      [window.innerWidth, window.innerHeight, window.outerWidth, window.devicePixelRatio,
       screen.width, visualViewport && visualViewport.scale, document.documentElement.clientWidth].join("/")
    JS
    "window=#{window.width}x#{window.height} inner/innerH/outer/dpr/screen/scale/client=#{metrics} ua=#{page.evaluate_script("navigator.userAgent")}"
  end

  # 失敗した例の後に出す、サーバーが受けた最後のリクエストと chromedriver の最後の命令。
  # 「サーバーが応答しなかった」のか「ブラウザが命令を返さなかった」のかを、ブラウザに触らずに切り分ける
  #
  # @return [String]
  def browser_diagnostics
    test_log = Rails.root.join("log/test.log")
    requests = test_log.exist? ? test_log.readlines.grep(/^(Started|Completed)/).last(20) : []
    driver = CHROMEDRIVER_LOG.exist? ? CHROMEDRIVER_LOG.readlines.last(40) : []
    [ "== 失敗時の診断: #{RSpec.current_example.full_description}",
      "-- log/test.log（Started / Completed の末尾）", *requests,
      "-- log/chromedriver.log の末尾", *driver ].map { |line| line.chomp[0, 300] }.join("\n")
  end

  private

  # @param suffix [String, nil]
  # @return [String] ファイル名（拡張子なし）。英数字・ハイフン以外は _ に
  def screenshot_name(suffix)
    example = RSpec.current_example
    spec_name = File.basename(example.metadata[:file_path], "_spec.rb")
    [ spec_name, example.description, suffix ].compact.join("_").gsub(/[^[:word:]-]+/, "_")
  end

  # rspec-rails の after（失敗時スクショ → Capybara.reset_sessions!）より先に走らせるため、
  # include 時に group の after として登録する（config.after は group の後に走るので間に合わない）。
  # 同じ group の after は後に登録したものが先に走る（LIFO）ので、この include が rspec-rails の
  # SystemExampleGroup の include（rails_helper の `require "rspec/rails"`）より後であることが前提。
  # rails_helper で support の読み込みを `require "rspec/rails"` より上に動かすと静かに逆転する。
  # 例ごとの 1 枚が撮れていることは spec/system/smoke_spec.rb の after(:context) が確認する。
  # スクショの失敗でテスト結果は隠さない。
  #
  # @param base [Class] include した example group
  # @return [void]
  def self.included(base)
    base.after do |example|
      # 診断はファイルを読むだけなので、ブラウザが固まっていても先に出せる
      warn browser_diagnostics if example.exception
      screenshot!
    rescue StandardError => e
      warn "screenshot! failed: #{e.class}: #{e.message}"
    end
  end
end

RSpec.configure do |config|
  config.include SystemScreen, type: :system

  config.before(:each, type: :system) do
    http_client = Selenium::WebDriver::Remote::Http::Default.new(read_timeout: SystemScreen::DRIVER_READ_TIMEOUT_SECONDS)
    service = Selenium::WebDriver::Service.chrome(args: [ "--log-path=#{SystemScreen::CHROMEDRIVER_LOG}" ])
    driven_by :selenium, using: :headless_chrome, screen_size: SystemScreen::SCREEN_SIZE, options: { http_client: http_client, service: service } do |options|
      SystemScreen::QUIET_CHROME_ARGS.each { |arg| options.add_argument(arg) }
      # window-size だけだとブラウザ枠の分だけ viewport が狭くなる。端末エミュレーションで CSS 幅を 390 に固定する
      options.add_emulation(
        device_metrics: { width: SystemScreen::SCREEN_SIZE[0], height: SystemScreen::SCREEN_SIZE[1], pixelRatio: 3, touch: true },
        user_agent: SystemScreen::IPHONE_USER_AGENT
      )
    end
  end
end
