# system の型にすると、例の後のスクショが差し替えた Selenium::WebDriver.for で Capybara の Chrome を作りに行く。
RSpec.describe "Chrome の起こし（SystemScreen.warm_up_chrome!）" do
  let(:browser) { instance_double(Selenium::WebDriver::Driver, navigate: navigation, quit: nil) }
  let(:navigation) { instance_double(Selenium::WebDriver::Navigation, to: nil) }
  let(:created) { [] }

  before do
    allow(Selenium::WebDriver).to receive(:for).with(:chrome, hash_including(:options, :http_client)) do |_, opts|
      created << opts
      browser
    end
  end

  it "長い read timeout の使い捨ての Chrome で、system の例と同じ 390 幅・iPhone の UA のページを一度描かせて閉じ、かかった秒数を出す" do
    expect { SystemScreen.warm_up_chrome! }.to output(/Chrome warm-up: \d+\.\ds/).to_stderr

    opts = created.sole
    expect(opts[:http_client].read_timeout).to eq(SystemScreen::WARM_UP_READ_TIMEOUT_SECONDS)
    expect(opts[:http_client].read_timeout).to be > SystemScreen::DRIVER_READ_TIMEOUT_SECONDS
    emulation = opts[:options].emulation
    expect(emulation[:device_metrics]).to include(width: SystemScreen::SCREEN_SIZE[0], touch: false)
    expect(emulation[:user_agent]).to eq(SystemScreen::IPHONE_USER_AGENT)
    expect(opts[:options].args).to include(start_with("--headless"))
    expect(navigation).to have_received(:to).with(start_with("data:text/html"))
    expect(browser).to have_received(:quit)
  end

  it "描かせる命令が返らなくても閉じて、警告だけ出して例を始めさせる" do
    allow(navigation).to receive(:to).and_raise(Net::ReadTimeout)

    expect { SystemScreen.warm_up_chrome! }.to output(/Chrome warm-up failed/).to_stderr
    expect(browser).to have_received(:quit)
  end

  it "閉じる命令が返らなくても、例の read timeout で見切って例を始めさせる（待ちを例 1 回ぶんより延ばさない）" do
    allow(navigation).to receive(:to).and_raise(Net::ReadTimeout)
    allow(browser).to receive(:quit) { sleep }
    stub_const("SystemScreen::DRIVER_READ_TIMEOUT_SECONDS", 0.1)

    expect { SystemScreen.warm_up_chrome! }.to output(/Chrome warm-up failed to quit/).to_stderr
  end

  it "Chrome が立ち上がらなくても、警告だけ出して例を始めさせる" do
    allow(Selenium::WebDriver).to receive(:for).and_raise(Selenium::WebDriver::Error::SessionNotCreatedError)

    expect { SystemScreen.warm_up_chrome! }.to output(/Chrome warm-up failed/).to_stderr
  end
end
