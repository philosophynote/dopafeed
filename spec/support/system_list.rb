# Main の一覧で行を広げて、欄の中で読む。別窓は開かせず、開いた時刻が届くのを待ってから滞在を作る
module SystemList
  def expand(title)
    find("article", text: title).find_button("読む").click
    expect(find("li[id^='article_']", text: title)).to have_link("記事に遷移")
  end

  def read_in_list(title, dwell:)
    page.execute_script(<<~JS)
      document.addEventListener("click", (event) => { if (event.target.closest("a[target=_blank]")) event.preventDefault() }, true)
    JS
    reading = Article.find_by!(title: title).reading
    since = reading.reload.opened_at
    find("li[id^='article_']", text: title).find_link("記事に遷移").click
    Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until reading.reload.opened_at > since }
    reading.update_columns(opened_at: Time.current - dwell)
    find("li[id^='article_']", text: title).click_on("読み終えた")
  end
end

RSpec.configure do |config|
  config.include SystemList, type: :system
end
