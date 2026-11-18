RSpec.describe "判定を積む契機", type: :request do
  include_context "判定が設定済み"

  let(:threshold) { Dopamine.settings.dig(:read, :complete_after_seconds) }
  let(:noon) { Time.zone.local(2026, 10, 20, 12) }

  before { sign_in_as(create(:user)) }

  it "「読む」で行ができた記事の判定を積む（読むと決めた記事だけ。要約と同じ契機）" do
    article = create(:article, :awaiting_summary)

    post article_reading_path(article)

    expect(JudgeArticleJob).to have_been_enqueued.with(article).once
  end

  it "本文取得前の記事では積まない（取得を試し終えたときに積まれる）" do
    post article_reading_path(create(:article, content_fetched_at: nil))

    expect(JudgeArticleJob).not_to have_been_enqueued
  end

  it "継ぎ足す次の記事の判定を積む" do
    reading = create(:reading, article: create(:article, published_at: noon), opened_at: noon)
    following = create(:article, :awaiting_summary, published_at: noon - 1.hour)

    travel_to(noon + threshold) { post advance_reading_path(reading) }

    expect(JudgeArticleJob).to have_been_enqueued.with(following).once
  end

  it "記事を開き直したとき、判定待ちなら積み直す（予算切れで捨てた翌日）" do
    article = create(:article, :awaiting_summary, :opened)

    get read_article_path(article)

    expect(JudgeArticleJob).to have_been_enqueued.with(article).once
  end

  it "判定の行がある記事を開き直しても積まない" do
    article = create(:article_judgment, article: create(:article, :awaiting_summary, :opened)).article

    get read_article_path(article)

    expect(JudgeArticleJob).not_to have_been_enqueued
  end
end
