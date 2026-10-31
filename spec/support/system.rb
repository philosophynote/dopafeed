# iPhone の PWA が主戦場なので、システムテストは全部 390×844 の headless Chrome で回す。
# 例が終わるごとに tmp/screenshots/<spec 名>_<例の説明>.png を 1 枚残す（bin/screens が集めて PR に貼る）。
module SystemScreen
  # CSS ピクセルでの画面サイズ（幅, 高さ）
  SCREEN_SIZE = [ 390, 844 ].freeze
  # スクショの保存先
  SCREENSHOT_DIR = Rails.root.join("tmp/screenshots")
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
    base.after do
      screenshot!
    rescue StandardError => e
      warn "screenshot! failed: #{e.class}: #{e.message}"
    end
  end
end

RSpec.configure do |config|
  config.include SystemScreen, type: :system

  config.before(:each, type: :system) do
    driven_by :selenium, using: :headless_chrome, screen_size: SystemScreen::SCREEN_SIZE do |options|
      # window-size だけだとブラウザ枠の分だけ viewport が狭くなる。端末エミュレーションで CSS 幅を 390 に固定する
      options.add_emulation(
        device_metrics: { width: SystemScreen::SCREEN_SIZE[0], height: SystemScreen::SCREEN_SIZE[1], pixelRatio: 3, touch: true },
        user_agent: SystemScreen::IPHONE_USER_AGENT
      )
    end
  end
end
