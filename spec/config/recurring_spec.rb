RSpec.describe "config/recurring.yml" do
  let(:recurring) { YAML.safe_load(ERB.new(Rails.root.join("config/recurring.yml").read).result, aliases: true) }

  it "production で FetchAllFeedsJob を定期的に積む" do
    task = recurring.fetch("production").fetch("fetch_all_feeds")
    expect(task["class"]).to eq("FetchAllFeedsJob")
    expect(task["schedule"]).to be_present
  end

  it "要約は定期では積まない（「読む」を押した記事だけ。ADR 0015）" do
    classes = recurring.fetch("production").values.filter_map { |task| task["class"] }
    expect(classes.grep(/Summar/)).to be_empty
  end

  it "production で PurgeArticlesJob を定期的に積む" do
    task = recurring.fetch("production").fetch("purge_articles")
    expect(task["class"]).to eq("PurgeArticlesJob")
    expect(task["queue"]).to eq("feeds")
    expect(task["schedule"]).to be_present
  end

  it "production で Claude::WeeklyCommentJob を毎時積む（生成するかは Job が決める）" do
    task = recurring.fetch("production").fetch("weekly_comment")
    expect(task["class"]).to eq("Claude::WeeklyCommentJob")
    expect(task["queue"]).to eq("claude")
    expect(task["schedule"]).to match(/every hour/)
  end
end
