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
end
