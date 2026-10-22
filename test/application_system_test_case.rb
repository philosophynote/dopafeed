require "test_helper"

# iPhone の PWA が主戦場なので、システムテストは全部 390×844 の headless Chrome で回す。
# 各テストの終わりに tmp/screenshots/<test名>.png を 1 枚残す（bin/screens が集めて PR に貼る）。
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  SCREEN_SIZE = [ 390, 844 ].freeze
  SCREENSHOT_DIR = Rails.root.join("tmp/screenshots")
  IPHONE_USER_AGENT = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1".freeze

  driven_by :selenium, using: :headless_chrome, screen_size: SCREEN_SIZE do |options|
    # window-size だけだとブラウザ枠の分だけ viewport が狭くなる。端末エミュレーションで CSS 幅を 390 に固定する
    options.add_emulation(
      device_metrics: { width: SCREEN_SIZE[0], height: SCREEN_SIZE[1], pixelRatio: 3, touch: true },
      user_agent: IPHONE_USER_AGENT
    )
  end

  # Rails は before_teardown の中で Capybara のセッションを閉じる（その後の teardown では白紙になる）。
  # なので super より前に撮る。スクショの失敗でテスト結果は隠さない。
  def before_teardown
    screenshot!
  rescue StandardError => e
    warn "screenshot! failed: #{e.class}: #{e.message}"
  ensure
    super
  end

  # tmp/screenshots/<クラス名>_<テスト名>[_suffix].png に保存し、そのパスを返す
  def screenshot!(suffix = nil)
    SCREENSHOT_DIR.mkpath
    path = SCREENSHOT_DIR.join("#{screenshot_name(suffix)}.png")
    page.save_screenshot(path.to_s)
    path
  end

  private

  def screenshot_name(suffix)
    [ self.class.name.underscore, method_name.delete_prefix("test_"), suffix ]
      .compact.join("_").gsub(/[^[:word:]-]+/, "_")
  end
end
