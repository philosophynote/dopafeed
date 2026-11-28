RSpec.describe "画面テストのブラウザ", type: :system do
  def unused_port
    TCPServer.open("127.0.0.1", 0) { |socket| socket.addr[1] }
  end

  it "リセット後は別のポートにも接続でき、Cookie と localStorage が残らない" do
    service = page.driver.options.fetch(:service)
    service.port = unused_port
    visit new_session_path
    browser = page.driver.browser
    page.execute_script("document.cookie = 'example=1'; localStorage.setItem('example', '1')")

    service.port = unused_port
    Capybara.reset_sessions!
    visit new_session_path

    expect(page.driver.browser).not_to equal(browser)
    expect(page.evaluate_script("document.cookie")).not_to include("example=")
    expect(page.evaluate_script("localStorage.getItem('example')")).to be_nil
  end
end
