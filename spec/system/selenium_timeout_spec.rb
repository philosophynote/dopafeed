# ブラウザが応答しなくなると、以後の 1 操作ごとに Selenium の read timeout（既定 120 秒）まで待つ。
# 例の数だけ積み上がって CI が数十分になるので、短い上限が driver に効いていることと、
# 固まった後に新しい Chrome へ切り替わることを確かめる
RSpec.describe "Selenium driver", type: :system do
  it "read timeout は SystemScreen::DRIVER_READ_TIMEOUT_SECONDS" do
    http = page.driver.browser.send(:bridge).http
    expect(http.read_timeout).to eq(SystemScreen::DRIVER_READ_TIMEOUT_SECONDS)
  end

  # touch をエミュレーションすると固まる（spec/support/system.rb）。切れたままであることを保つ
  it "touch エミュレーションは切る（navigator.maxTouchPoints が 0）" do
    visit new_session_path
    expect(page.evaluate_script("navigator.maxTouchPoints")).to eq(0)
  end

  # chromedriver の合成 mouse click は届かないことがある（spec/support/system.rb）。JS の click() で送っていることを保つ
  it "click は要素の click() で送る（pointer イベントは起きない）" do
    visit new_session_path
    page.execute_script(<<~JS)
      window.__events = [];
      for (const type of ["pointerdown", "mousedown", "click"]) document.addEventListener(type, (e) => window.__events.push(type), true);
    JS

    click_on "Forgot password?"

    expect(page).to have_current_path(new_password_path)
    expect(page.evaluate_script("window.__events")).to eq([ "click" ])
  end

  it "restart_browser! は新しい driver と Chrome に切り替える" do
    visit new_session_path
    old_driver = page.driver
    old_session_id = old_driver.browser.send(:bridge).session_id

    expect { restart_browser! }.to output(/browser unresponsive/).to_stderr

    expect(page.driver).not_to equal(old_driver)
    expect(page.driver.browser.send(:bridge).session_id).not_to eq(old_session_id)
  end

  it "restart_browser! は quit が返らなくても切り替える" do
    visit new_session_path
    old_driver = page.driver
    allow(old_driver.browser.send(:bridge)).to receive(:quit).and_raise(Net::ReadTimeout)

    expect { restart_browser! }.to output(/quit failed/).to_stderr

    expect(page.driver).not_to equal(old_driver)
    expect(page).to have_no_text("Sign in")
  end
end
