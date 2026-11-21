module SystemScreen
  SCREEN_SIZE = [ 390, 844 ].freeze
  SCREENSHOT_DIR = Rails.root.join("tmp/screenshots")
  DRIVER_READ_TIMEOUT_SECONDS = 20
  WARM_UP_READ_TIMEOUT_SECONDS = 120
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

  # window-size だけだとブラウザ枠の分だけ viewport が狭くなる。端末エミュレーションで CSS 幅を 390 に固定する。
  # touch は false と明示する（省くと chromedriver は true 扱い）。true だと chromedriver が click を touch イベントで送り、
  # Chrome が touchEnd の応答を返さずに固まることがある
  def self.emulate_iphone(options)
    options.add_emulation(
      device_metrics: { width: SCREEN_SIZE[0], height: SCREEN_SIZE[1], pixelRatio: 3, touch: false },
      user_agent: IPHONE_USER_AGENT
    )
    options
  end

  # CI の新しいランナーで最初に立てた Chrome は、最初の命令が 20 秒を越えて返らないことがある。
  # 例の read timeout を延ばすと固まったときの待ちが全部延びるので、使い捨ての Chrome に初回の重さを肩代わりさせる。
  # プロファイルは chromedriver がセッションごとに作り直すので、温まるのはバイナリとフォントのキャッシュまで。
  def self.warm_up_chrome!
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    browser = nil
    Timeout.timeout(WARM_UP_READ_TIMEOUT_SECONDS) do
      options = emulate_iphone(Selenium::WebDriver::Options.chrome(args: [ "--headless=new", "--window-size=#{SCREEN_SIZE.join(",")}" ]))
      http_client = Selenium::WebDriver::Remote::Http::Default.new(read_timeout: WARM_UP_READ_TIMEOUT_SECONDS)
      browser = Selenium::WebDriver.for(:chrome, options: options, http_client: http_client)
      browser.navigate.to("data:text/html;charset=utf-8,<p>DopaFeed 読む 保存 図鑑</p>")
    end
    warn format("Chrome warm-up: %.1fs", Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
  rescue StandardError => e
    warn format("Chrome warm-up failed after %.1fs (examples start anyway): %s", Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, e.class)
  ensure
    quit_warm_up(browser)
  end

  # 固まった Chrome への quit も返らないので、例 1 回ぶんの待ちで見切る。quit の ensure が chromedriver を止める。
  def self.quit_warm_up(browser)
    Timeout.timeout(DRIVER_READ_TIMEOUT_SECONDS) { browser&.quit }
  rescue StandardError => e
    warn "Chrome warm-up failed to quit: #{e.class}"
  end
  private_class_method :quit_warm_up

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

  config.when_first_matching_example_defined(type: :system) do
    config.before(:suite) { SystemScreen.warm_up_chrome! }
  end

  config.before(:each, type: :system) do
    http_client = Selenium::WebDriver::Remote::Http::Default.new(read_timeout: SystemScreen::DRIVER_READ_TIMEOUT_SECONDS)
    service = Selenium::WebDriver::Service.chrome(args: [ "--log-path=#{SystemScreen::CHROMEDRIVER_LOG}" ])
    driven_by :selenium, using: :headless_chrome, screen_size: SystemScreen::SCREEN_SIZE, options: { http_client: http_client, service: service } do |options|
      SystemScreen.emulate_iphone(options)
    end
  end
end
