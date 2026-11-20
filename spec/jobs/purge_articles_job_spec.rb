RSpec.describe PurgeArticlesJob, type: :job do
  it "期限を過ぎた記事を消す" do
    allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.merge(retention: { dismissed_days: 1, unread_days: 3 }))
    create(:article, dismissed_at: 2.days.ago)
    kept = create(:article)

    described_class.perform_now

    expect(Article.pluck(:id)).to eq([ kept.id ])
  end
end
