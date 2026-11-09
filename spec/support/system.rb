module SystemScreen
  SCREEN_SIZE = [ 390, 844 ].freeze
  SCREENSHOT_DIR = Rails.root.join("tmp/screenshots")
  DRIVER_READ_TIMEOUT_SECONDS = 20
  CHROMEDRIVER_LOG = Rails.root.join("log/chromedriver.log")
  IPHONE_USER_AGENT = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1".freeze

  def screenshot!(suffix = nil)
    SCREENSHOT_DIR.mkpath
    path = screenshot_path(suffix)
    page.save_screenshot(path.to_s)
    path
  end

  def screenshot_path(suffix = nil)
    SCREENSHOT_DIR.join("#{screenshot_name(suffix)}.png")
  end

  # headless Chrome の最初のページでは innerWidth だけが 609 になることがあるため、CSS が使う clientWidth を測る。
  def viewport_width
    page.document.synchronize do
      width = page.evaluate_script("document.documentElement.clientWidth")
      raise Capybara::ElementNotFound, "viewport #{width}px" unless width == SCREEN_SIZE[0]

      width
    end
  rescue Capybara::ElementNotFound
    page.evaluate_script("document.documentElement.clientWidth")
  end

  def media_query_sees_screen_width?
    page.evaluate_script("window.matchMedia('(width: #{SCREEN_SIZE[0]}px)').matches")
  end

  def viewport_diagnostics
    window = page.driver.browser.manage.window.size
    metrics = page.evaluate_script(<<~JS)
      [window.innerWidth, window.innerHeight, window.outerWidth, window.devicePixelRatio,
       screen.width, visualViewport && visualViewport.scale, document.documentElement.clientWidth].join("/")
    JS
    "window=#{window.width}x#{window.height} inner/innerH/outer/dpr/screen/scale/client=#{metrics} ua=#{page.evaluate_script("navigator.userAgent")}"
  end

  # 固まったブラウザに命令を足すと再び待つため、診断はログから読む。
  def browser_diagnostics
    test_log = Rails.root.join("log/test.log")
    requests = test_log.exist? ? test_log.readlines.grep(/^(Started|Completed)/).last(20) : []
    driver = CHROMEDRIVER_LOG.exist? ? CHROMEDRIVER_LOG.readlines.last(40) : []
    [ "== 失敗時の診断: #{RSpec.current_example.full_description}",
      "-- log/test.log（Started / Completed の末尾）", *requests,
      "-- log/chromedriver.log の末尾", *driver ].map { |line| line.chomp[0, 300] }.join("\n")
  end

  # 同じセッションを使い続けると以後の全命令がタイムアウトまで待つため、固まったセッションは捨てる。
  # quit も返らない場合がある。直後の失敗スクショは新しい Chrome の空白になる。
  def restart_browser!
    warn "browser unresponsive: quitting so a new Chrome starts"
    page.driver.quit
  rescue StandardError => e
    warn "browser quit failed (restarting anyway): #{e.class}"
  ensure
    Capybara.current_session.quit
  end

  private

  def screenshot_name(suffix)
    example = RSpec.current_example
    spec_name = File.basename(example.metadata[:file_path], "_spec.rb")
    [ spec_name, example.description, suffix ].compact.join("_").gsub(/[^[:word:]-]+/, "_")
  end

  # config.after では Capybara の reset に間に合わないため、group の after に登録する。
  # after は LIFO なので、support を rspec/rails より先に読むと順序が逆転する。
  def self.included(base)
    base.after do |example|
      unresponsive = example.exception.is_a?(Net::ReadTimeout)
      warn browser_diagnostics if example.exception
      screenshot!
    rescue StandardError => e
      unresponsive ||= e.is_a?(Net::ReadTimeout)
      warn "screenshot! failed: #{e.class}: #{e.message}"
    ensure
      restart_browser! if unresponsive
    end
  end
end

RSpec.configure do |config|
  config.include SystemScreen, type: :system

  config.before(:each, type: :system) do
    http_client = Selenium::WebDriver::Remote::Http::Default.new(read_timeout: SystemScreen::DRIVER_READ_TIMEOUT_SECONDS)
    service = Selenium::WebDriver::Service.chrome(args: [ "--log-path=#{SystemScreen::CHROMEDRIVER_LOG}" ])
    driven_by :selenium, using: :headless_chrome, screen_size: SystemScreen::SCREEN_SIZE, options: { http_client: http_client, service: service } do |options|
      # window-size だけだとブラウザ枠の分だけ viewport が狭くなる。端末エミュレーションで CSS 幅を 390 に固定する。
      # touch は false と明示する（省くと chromedriver は true 扱い）。true だと chromedriver が click を touch イベントで送り、
      # Chrome が touchEnd の応答を返さずに固まることがある
      options.add_emulation(
        device_metrics: { width: SystemScreen::SCREEN_SIZE[0], height: SystemScreen::SCREEN_SIZE[1], pixelRatio: 3, touch: false },
        user_agent: SystemScreen::IPHONE_USER_AGENT
      )
    end
  end
end
