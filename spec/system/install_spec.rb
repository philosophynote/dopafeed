# Install（docs/screens/install.md）の standalone の分岐と、アイコンのバッジ（Badging API）。
# iOS の「ホーム画面から開いた」は Selenium では作れないので、navigator.standalone（か display-mode）を偽って同じ分岐を踏ませる。
# setAppBadge / clearAppBadge は呼ばれた引数を window.__badges に積む代物に置き換え、「呼んだ」ことまでを検証する
# （iOS で本当にバッジが出るかは通知の許可に掛かるので、実機でしか分からない）
RSpec.describe "Install", type: :system do
  # 新しい文書ごとに先回りで入れるスクリプト（ページの JS より先に走るので、Stimulus の connect が見る値を変えられる）。
  # ブラウザは例をまたいで使い回されるので、入れたものは after で外す
  # push: は Notification と service worker の pushManager の偽物の状態。
  # :default は未許可（requestPermission で許可になる）、:denied は拒否済み、:subscribed は許可済みで購読あり。
  # 購読の有無と subscribe を呼んだ回数は sessionStorage に持ち、文書をまたいでも残す（再訪で再購読しないことを見るため。
  # 許可は購読と一緒に granted になる）
  def emulate_standalone!(via: :navigator, push: nil, key: vapid["VAPID_PUBLIC_KEY"])
    detection = if via == :navigator
      'Object.defineProperty(navigator, "standalone", { value: true, configurable: true });'
    else
      'window.matchMedia = (query) => ({ matches: query === "(display-mode: standalone)", media: query });'
    end
    @standalone_script = page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
      #{detection}
      window.__badges = [];
      navigator.setAppBadge = (count) => { window.__badges.push(count); return Promise.resolve(); };
      navigator.clearAppBadge = () => { window.__badges.push("clear"); return Promise.resolve(); };
      #{push_stub(push, key: key) if push}
    JS
  end

  # key: は端末の購読が作られた公開鍵（base64url）。サーバーの鍵と違えば Install が解除するはず
  def push_stub(state, key:)
    <<~JS
      (() => {
        if (#{state == :subscribed}) sessionStorage.setItem("__push_subscribed", "1");
        window.Notification = {
          permission: #{state == :denied ? '"denied"' : 'sessionStorage.getItem("__push_subscribed") ? "granted" : "default"'},
          requestPermission: () => { window.Notification.permission = "granted"; return Promise.resolve("granted"); }
        };
        const base64 = "#{key}".replace(/-/g, "+").replace(/_/g, "/");
        const keyBytes = Uint8Array.from(atob(base64 + "=".repeat((4 - (base64.length % 4)) % 4)), (c) => c.charCodeAt(0));
        const subscription = {
          endpoint: "https://push.example.com/sub/stub",
          options: { applicationServerKey: keyBytes.buffer },
          toJSON() { return { endpoint: this.endpoint, keys: { p256dh: "BStubKey", auth: "stubauth" } }; },
          unsubscribe: () => { sessionStorage.removeItem("__push_subscribed"); sessionStorage.setItem("__unsubscribed", "1"); return Promise.resolve(true); }
        };
        const registration = {
          pushManager: {
            getSubscription: () => Promise.resolve(sessionStorage.getItem("__push_subscribed") ? subscription : null),
            subscribe: () => {
              sessionStorage.setItem("__push_subscribed", "1");
              sessionStorage.setItem("__subscribe_calls", String(Number(sessionStorage.getItem("__subscribe_calls")) + 1));
              return Promise.resolve(subscription);
            }
          }
        };
        Object.defineProperty(navigator, "serviceWorker", {
          configurable: true,
          value: { ready: Promise.resolve(registration), register: () => Promise.resolve(registration), getRegistration: () => Promise.resolve(registration) }
        });
      })();
    JS
  end

  let(:vapid) { { "VAPID_PUBLIC_KEY" => WebPush.generate_key.public_key, "VAPID_PRIVATE_KEY" => "private", "VAPID_SUBJECT" => "mailto:nao@example.com" } }

  after do
    next unless @standalone_script

    page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: @standalone_script["identifier"])
  rescue Selenium::WebDriver::Error::WebDriverError => e
    # ブラウザが固まった例の後に、外す命令でもう一度 read timeout を待たない（次の例は新しい Chrome で始まる）
    warn "standalone stub not removed: #{e.class}"
  end

  # Stimulus が connect するまで待ってから最後の呼び出しを見る
  def expect_last_badge(value)
    page.document.synchronize do
      last = page.evaluate_script("window.__badges[window.__badges.length - 1]")
      raise Capybara::ElementNotFound, "last badge call was #{last.inspect}" unless last == value
    end
  end

  it "Safari のタブで開くと手順 3 段と注記が出て「通知を許可する」は無効" do
    sign_in
    visit install_path

    expect(page).to have_css("ol[aria-label='手順'] li", count: 3)
    expect(page).to have_button("通知を許可する", disabled: true)
    expect(page).to have_text("Safari のタブのままでは通知もバッジも使えません")
    expect(page).to have_no_text("ホーム画面から開いています")
  end

  it "ホーム画面から開く（navigator.standalone）と注記が変わり、アイコンに未読数のバッジが付く" do
    create_list(:article, 3)
    emulate_standalone!

    sign_in
    expect(page).to have_css("[data-unread-badge]", text: "3")
    expect_last_badge(3)

    visit install_path
    expect(page).to have_text("ホーム画面から開いています")
    expect(page).to have_no_text("Safari のタブのままでは通知もバッジも使えません")
    expect_last_badge(3)
    screenshot!("standalone")
  end

  it "display-mode: standalone でも同じ分岐に入る" do
    emulate_standalone!(via: :display_mode)

    sign_in
    visit install_path

    expect(page).to have_text("ホーム画面から開いています")
  end

  it "未読が 0 ならバッジを消す" do
    emulate_standalone!

    sign_in
    expect(page).to have_text("全部読んだ")
    expect_last_badge("clear")
  end

  def subscribe_calls
    page.evaluate_script('Number(sessionStorage.getItem("__subscribe_calls"))')
  end

  it "ホーム画面から「通知を許可する」→ 許可 → 購読がサーバーに残り「通知は有効」。再訪しても再購読しない（保存は冪等）" do
    emulate_standalone!(push: :default)

    with_env(vapid) do
      sign_in
      visit install_path
      expect(page).to have_button("通知を許可する", disabled: false)

      click_on "通知を許可する"

      expect(page).to have_button("通知は有効", disabled: true)
      expect(PushSubscription.count).to eq(1)
      expect(PushSubscription.last).to have_attributes(endpoint: "https://push.example.com/sub/stub", p256dh: "BStubKey", auth: "stubauth")
      screenshot!("enabled")

      expect(subscribe_calls).to eq(1)

      visit install_path
      expect(page).to have_button("通知は有効", disabled: true)
      expect(subscribe_calls).to eq(1)
      expect(PushSubscription.count).to eq(1)
    end
  end

  it "端末の購読がサーバーと違う鍵で作られていれば（鍵の交換後）解除して、ボタンを有効に戻す" do
    emulate_standalone!(push: :subscribed, key: WebPush.generate_key.public_key)

    with_env(vapid) do
      sign_in
      visit install_path

      expect(page).to have_button("通知を許可する", disabled: false)
      expect(page.evaluate_script('sessionStorage.getItem("__unsubscribed")')).to eq("1")
      expect(PushSubscription.count).to eq(0)
    end
  end

  it "許可済みで購読もある端末なら、開いただけで保存し直して「通知は有効」" do
    emulate_standalone!(push: :subscribed)

    with_env(vapid) do
      sign_in
      visit install_path

      expect(page).to have_button("通知は有効", disabled: true)
      expect(PushSubscription.count).to eq(1)
      expect(subscribe_calls).to eq(0)
    end
  end

  it "通知を拒否していると「iPhone の設定から通知を許可してください」が出てボタンは無効" do
    emulate_standalone!(push: :denied)

    with_env(vapid) do
      sign_in
      visit install_path

      expect(page).to have_text("iPhone の設定から通知を許可してください")
      expect(page).to have_button("通知を許可する", disabled: true)
      screenshot!("denied")
    end
  end

  it "Safari のタブでは鍵があってもボタンは無効のまま" do
    with_env(vapid) do
      sign_in
      visit install_path

      expect(page).to have_button("通知を許可する", disabled: true)
    end
  end

  it "「興味なし」で未読が減ると、アイコンのバッジも書き直す" do
    create_list(:article, 2)
    emulate_standalone!

    sign_in
    expect_last_badge(2)
    # 興味なしは左スワイプが隠れた form を送る。ここではバッジだけ見るので form を直に送る
    page.execute_script("document.querySelector('article form[data-swipe-target=form]').requestSubmit()")

    expect(page).to have_text("元に戻す")
    expect_last_badge(1)
  end
end
