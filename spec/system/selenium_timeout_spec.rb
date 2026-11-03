# ブラウザが応答しなくなると、以後の 1 操作ごとに Selenium の read timeout（既定 120 秒）まで待つ。
# 例の数だけ積み上がって CI が数十分になるので、短い上限が driver に効いていることを確かめる
RSpec.describe "Selenium driver", type: :system do
  it "read timeout は SystemScreen::DRIVER_READ_TIMEOUT_SECONDS" do
    http = page.driver.browser.send(:bridge).http
    expect(http.read_timeout).to eq(SystemScreen::DRIVER_READ_TIMEOUT_SECONDS)
  end
end
