module SystemReader
  def read_from_saved(article)
    article.bookmark!
    visit saved_path
    within("article", text: article.title) { click_on "読む" }
    expect(page).to have_current_path(read_article_path(article))
  end

  def judgment_pending
    allow(Reading).to receive(:tier_at_open).and_return(nil)
  end

  # 帯が購読を始める前に配ると届かず、取り直しの側を通ってしまう
  def judgment_arrives(article, tier)
    expect(page).to have_css("#rarity_reading_#{article.reload.reading.id} turbo-cable-stream-source[connected]", visible: :all)
    create(:article_judgment, article: article, **scores_for(tier))
    JudgeArticleJob.settle(article)
  end
end

RSpec.configure do |config|
  config.include SystemReader, type: :system
end
