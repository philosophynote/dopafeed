# ブラウザが応答しなくなると、以後の 1 操作ごとに Selenium の read timeout（既定 120 秒）まで待つ。
# 例の数だけ積み上がって CI が数十分になるので、短い上限が driver に効いていることと、
# 固まった後に新しい Chrome へ切り替わることを確かめる。
# 固まる原因だった touch エミュレーションと、合成 click の代わりの JS click も、戻されたら落ちるようにここで見る
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

  # chromedriver の合成 mouse click は届かないことがある（spec/support/system_click.rb）。JS の click() で送っていることを保つ。
  # 見たいのは起きるイベントだけなので、click を止めて遷移させず、window を生かしたまま記録を読む
  it "click は要素の click() で送る（pointer イベントは起きない）" do
    # 正しいパスワードを入れておく。click が止まらず送信されたら Main へ進み、下の current_path で落ちる
    create(:user)
    visit new_session_path
    fill_in "パスワード", with: "password"
    page.execute_script(<<~JS)
      window.__events = [];
      for (const type of ["pointerdown", "mousedown", "click"]) {
        document.addEventListener(type, (event) => { window.__events.push(type); event.preventDefault(); }, true);
      }
    JS

    click_on "ログイン"

    expect(page.evaluate_script("window.__events")).to eq([ "click" ])
    expect(page).to have_current_path(new_session_path)
  end

  # 覆われた要素を JS click で押してしまわないよう、chromedriver に任せて従来どおり落とす
  it "覆われた要素の click は chromedriver に任せて落ちる" do
    visit new_session_path
    page.execute_script(<<~JS)
      const cover = document.createElement("div");
      cover.style.cssText = "position: fixed; inset: 0; z-index: 100; background: rgba(0, 0, 0, 0.5)";
      document.body.appendChild(cover);
    JS

    expect { click_on "ログイン" }.to raise_error(Selenium::WebDriver::Error::ElementClickInterceptedError)
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
    expect(page).to have_no_text("DopaFeed")
  end
end
