# Reader へは Main から来ない（Main の行は下に広がる。ADR 0019）。残る入口の Saved の行から「読む」→ ルーレット → Reader と進む
module SystemReader
  def read_from_saved(article)
    article.bookmark!
    visit saved_path
    within("article", text: article.title) { click_on "読む" }
    expect(page).to have_current_path(read_article_path(article))
  end
end

RSpec.configure do |config|
  config.include SystemReader, type: :system
end
