# Solid Queue の定期実行（config/recurring.yml）に取得 Job と要約 Job が載っていることを守る
RSpec.describe "config/recurring.yml" do
  let(:recurring) { YAML.safe_load(ERB.new(Rails.root.join("config/recurring.yml").read).result, aliases: true) }

  it "production で FetchAllFeedsJob を定期的に積む" do
    task = recurring.fetch("production").fetch("fetch_all_feeds")
    expect(task["class"]).to eq("FetchAllFeedsJob")
    expect(task["schedule"]).to be_present
  end

  it "production で Claude::SummarizePendingArticlesJob を定期的に積む" do
    task = recurring.fetch("production").fetch("summarize_pending_articles")
    expect(task["class"]).to eq("Claude::SummarizePendingArticlesJob")
    expect(task["schedule"]).to be_present
  end
end
