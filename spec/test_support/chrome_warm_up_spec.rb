# system の型にすると、例の後のスクショが差し替えた Selenium::WebDriver.for で Capybara の Chrome を作りに行く。
RSpec.describe "Chrome の起こし" do
  describe "SystemScreen.warm_up_once（子プロセスの中身）" do
    let(:browser) { instance_double(Selenium::WebDriver::Driver, navigate: navigation, quit: nil) }
    let(:navigation) { instance_double(Selenium::WebDriver::Navigation, to: nil) }
    let(:created) { [] }

    before do
      allow(Selenium::WebDriver).to receive(:for).with(:chrome, hash_including(:options, :http_client)) do |_, opts|
        created << opts
        browser
      end
    end

    it "長い read timeout の Chrome で、system の例と同じ 390 幅・iPhone の UA のページを一度描かせて閉じる" do
      expect(SystemScreen.warm_up_once).to be(true)

      opts = created.sole
      expect(opts[:http_client].read_timeout).to eq(SystemScreen::WARM_UP_SECONDS)
      expect(opts[:http_client].read_timeout).to be > SystemScreen::DRIVER_READ_TIMEOUT_SECONDS
      expect(opts[:options].emulation[:device_metrics]).to include(width: SystemScreen::SCREEN_SIZE[0], touch: false)
      expect(opts[:options].emulation[:user_agent]).to eq(SystemScreen::IPHONE_USER_AGENT)
      expect(opts[:options].args).to include(start_with("--headless"))
      expect(navigation).to have_received(:to).with(start_with("data:text/html"))
      expect(browser).to have_received(:quit)
    end

    it "Chrome が立ち上がらなければ、警告を出して失敗を返す" do
      allow(Selenium::WebDriver).to receive(:for).and_raise(Selenium::WebDriver::Error::SessionNotCreatedError)

      expect { expect(SystemScreen.warm_up_once).to be(false) }.to output(/Chrome warm-up error/).to_stderr
    end
  end

  describe "SystemScreen.warm_up_chrome!（親の待ち）" do
    it "子が終われば、かかった秒数を出す" do
      allow(SystemScreen).to receive(:warm_up_once).and_return(true)

      expect { SystemScreen.warm_up_chrome! }.to output(/Chrome warm-up: \d+\.\ds/).to_stderr
    end

    it "子が失敗しても、警告だけ出して例を始めさせる" do
      allow(SystemScreen).to receive(:warm_up_once).and_return(false)

      expect { SystemScreen.warm_up_chrome! }.to output(/Chrome warm-up failed after .*exit 1/).to_stderr
    end

    it "子が固まったら、WARM_UP_SECONDS で子とその子孫ごと止めて例を始めさせる（後始末の待ちも足さない）" do
      stub_const("SystemScreen::WARM_UP_SECONDS", 0.5)
      marker = Rails.root.join("tmp/warm_up_grandchild_#{Process.pid}")
      allow(SystemScreen).to receive(:warm_up_once) do
        grandchild = spawn("sleep 30")
        File.write(marker, grandchild.to_s)
        sleep
      end

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { SystemScreen.warm_up_chrome! }.to output(/Chrome warm-up failed after .*timeout/).to_stderr

      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5
      # 親を失った孫は止まった後もしばらくゾンビで残るので、ps の状態で見る
      expect(`ps -o stat= -p #{Integer(marker.read)}`.strip).to eq("").or start_with("Z")
    ensure
      marker&.delete if marker&.exist?
    end
  end

  describe "SystemScreen.system_examples_to_run?" do
    def group(type) = double(metadata: { type: type })

    it "filter を通った system の例があるときだけ真（定義されただけの system の例では起こさない）" do
      system_group = group(:system)
      request_group = group(:request)
      world = double(all_example_groups: [ request_group, system_group ])

      allow(world).to receive(:filtered_examples).and_return({ request_group => [ :example ], system_group => [] })
      expect(SystemScreen.system_examples_to_run?(world)).to be(false)

      allow(world).to receive(:filtered_examples).and_return({ request_group => [], system_group => [ :example ] })
      expect(SystemScreen.system_examples_to_run?(world)).to be(true)
    end
  end
end
