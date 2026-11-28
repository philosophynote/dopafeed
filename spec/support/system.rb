module SystemScreen
  SCREEN_SIZE = [ 390, 844 ].freeze
  SCREENSHOT_DIR = Rails.root.join("tmp/screenshots")
  DRIVER_READ_TIMEOUT_SECONDS = 20
  WARM_UP_SECONDS = 120
  CHROMEDRIVER_LOG = Rails.root.join("log/chromedriver.log")
  IPHONE_USER_AGENT = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1".freeze

  def sample_image_path
    ActionController::Base.helpers.image_path("icon.png")
  end

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

  def self.chrome_options
    emulate_iphone(Selenium::WebDriver::Options.chrome(args: [
      "--headless=new", "--disable-search-engine-choice-screen", "--window-size=#{SCREEN_SIZE.join(',')}"
    ]))
  end

  def self.chrome_http_client
    Selenium::WebDriver::Remote::Http::Default.new(read_timeout: DRIVER_READ_TIMEOUT_SECONDS)
  end

  # CI の新しいランナーで最初に立てた Chrome は、最初の命令が 20 秒を越えて返らないことがある。
  # 例の read timeout を延ばすと固まったときの待ちが全部延びるので、使い捨ての Chrome に初回の重さを肩代わりさせる。
  # プロファイルは chromedriver がセッションごとに作り直すので、温まるのはバイナリとフォントのキャッシュまで。
  # Timeout では Selenium の後始末（chromedriver の停止待ち）までは切れず、起動途中の失敗では chromedriver が残る。
  # そこで子プロセスで起こし、時間切れならプロセスグループごと止めて、待ちを WARM_UP_SECONDS に収める。
  def self.warm_up_chrome!
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    pid = fork do
      Process.setpgid(0, 0)
      exit!(warm_up_once ? 0 : 1)
    end
    begin
      Process.setpgid(pid, pid)
    rescue SystemCallError
      nil # 子が先に自分で分けたか、もう終わっている
    end
    status = wait_for_warm_up(pid, started + WARM_UP_SECONDS)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    if status&.success?
      warn format("Chrome warm-up: %.1fs", elapsed)
    else
      warn format("Chrome warm-up failed after %.1fs (examples start anyway): %s", elapsed, status ? "exit #{status.exitstatus}" : "timeout")
    end
  end

  def self.warm_up_once
    http_client = Selenium::WebDriver::Remote::Http::Default.new(read_timeout: WARM_UP_SECONDS)
    browser = Selenium::WebDriver.for(:chrome, options: chrome_options, http_client: http_client)
    browser.navigate.to("data:text/html;charset=utf-8,<p>DopaFeed 読む 保存 図鑑</p>")
    browser.quit
    true
  rescue StandardError => e
    warn "Chrome warm-up error: #{e.class}"
    false
  end

  def self.wait_for_warm_up(pid, deadline)
    loop do
      _, status = Process.wait2(pid, Process::WNOHANG)
      return status if status
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.1
    end
    begin
      Process.kill(:KILL, -pid)
    rescue Errno::ESRCH
      nil
    end
    Process.wait(pid)
    nil
  end
  private_class_method :wait_for_warm_up

  # 定義されただけで filter に外された system の例（-e や --tag）では Chrome を立てない。
  def self.system_examples_to_run?(world = RSpec.world)
    world.all_example_groups.any? { |group| group.metadata[:type] == :system && world.filtered_examples[group].any? }
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

Capybara.register_driver :dopafeed_chrome do |app|
  service = Selenium::WebDriver::Service.chrome(args: [ "--log-path=#{SystemScreen::CHROMEDRIVER_LOG}" ])
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: SystemScreen.chrome_options, http_client: SystemScreen.chrome_http_client, service: service).tap do |driver|
    # Chrome は Capybara のワイルドカードによる消去を拒否する。セッションを閉じれば Cookie やストレージも残らない。
    def driver.reset!
      quit
    ensure
      options[:http_client] = SystemScreen.chrome_http_client
    end
  end
end

RSpec.configure do |config|
  config.include SystemScreen, type: :system

  config.before(:suite) { SystemScreen.warm_up_chrome! if SystemScreen.system_examples_to_run? }

  config.before(:each, type: :system) do
    driven_by :dopafeed_chrome
  end
end
