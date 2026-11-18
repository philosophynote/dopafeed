RSpec.describe Reading, type: :model do
  let(:reset_hour) { Dopamine.settings.dig(:daily_goal, :reset_hour) }

  it "article, opened_at が必須" do
    reading = Reading.new
    expect(reading).not_to be_valid
    expect(reading.errors[:article]).to include("must exist")
    expect(reading.errors[:opened_at]).to include("can't be blank")
  end

  it "tier は空（判定中）か、dopamine.yml の cards.rarities の name だけ" do
    expect(build(:reading, :pending)).to be_valid

    article = create(:article)
    Dopamine.rarity_names.each do |name|
      expect(build(:reading, article: article, tier: name)).to be_valid, "#{name} は有効な tier"
    end

    bogus = build(:reading, article: article, tier: "legendary")
    expect(bogus).not_to be_valid
    expect(bogus.errors[:tier]).to include("is not included in the list")
  end

  it "jackpot? は tier が Dopamine.top_rarity（yml の最後の段）のときだけ" do
    expect(build(:reading, tier: Dopamine.top_rarity[:name])).to be_jackpot
    expect(build(:reading, tier: Dopamine.rarity_names.first)).not_to be_jackpot
    expect(build(:reading, :pending)).not_to be_jackpot
  end

  it "1 記事 1 行（同じ記事に 2 行目は作れない）" do
    existing = create(:reading)
    dup = build(:reading, article: existing.article)
    expect(dup).not_to be_valid
    expect(dup.errors[:article_id]).to include("has already been taken")
  end

  it "数値の XP は持たない（完読した行がそのままカード。ADR 0020）" do
    expect(Reading.column_names).not_to include("xp", "combo_multiplier")
  end

  it "card_count は完読した行の数（開いただけ・未完は数えない）" do
    create(:reading, :completed)
    create(:reading, :completed, :jackpot)
    create(:reading)
    create(:reading, opened_at: Time.zone.local(2026, 10, 6, 8), returned_at: Time.zone.local(2026, 10, 6, 8, 0, 5))
    expect(Reading.card_count).to eq(2)
  end

  it "completed? は completed_at の有無" do
    expect(build(:reading, :completed)).to be_completed
    expect(build(:reading)).not_to be_completed
  end

  it "dwell_seconds は読み終えた時刻 − 開いた時刻。判定前なら nil" do
    completed = build(:reading, :completed)
    expect(completed.dwell_seconds).to eq(4 * 60 + 12)
    expect(build(:reading).dwell_seconds).to be_nil
  end

  it "completed_at があるなら returned_at も要る" do
    reading = build(:reading, :completed, returned_at: nil)
    expect(reading).not_to be_valid
    expect(reading.errors[:returned_at]).to include("can't be blank")
  end

  it "completed スコープは completed_at のある行だけ" do
    completed = create(:reading, :completed)
    create(:reading)
    expect(Reading.completed).to contain_exactly(completed)
  end

  it "on(day) は reset_hour 基準の 1 日で completed_at を絞る" do
    day = Date.new(2026, 10, 20)
    just_before = complete(at: Time.zone.local(2026, 10, 20, reset_hour) - 1.minute)
    at_start = complete(at: Time.zone.local(2026, 10, 20, reset_hour))
    last_minute = complete(at: Time.zone.local(2026, 10, 21, reset_hour) - 1.minute)
    next_day_start = complete(at: Time.zone.local(2026, 10, 21, reset_hour))
    opened_only = create(:reading, opened_at: Time.zone.local(2026, 10, 20, reset_hour) + 1.hour)

    expect(Reading.on(day)).to contain_exactly(at_start, last_minute)
    expect(Reading.on(day - 1)).to include(just_before)
    expect(Reading.on(day + 1)).to include(next_day_start), "翌日の reset_hour ちょうどは翌日分（SQL の < で切る）"
    expect(Reading.on(day)).not_to include(opened_only), "completed_at が nil の行は除く"
  end

  def complete(at:)
    create(:reading, :completed, opened_at: at - 1.minute, returned_at: at, completed_at: at)
  end

  describe ".open!" do
    let(:at) { Time.zone.local(2026, 10, 20, 12) }
    let(:rare) { Dopamine.rarity_names.second }

    context "判定が設定済み" do
      include_context "判定が設定済み"

      it "行が無ければ、枠を空（判定中）のまま opened_at を今にして作る" do
        reading = Reading.open!(create(:article), at: at)

        expect(reading).to be_persisted
        expect(reading.tier).to be_nil
        expect(reading.opened_at).to eq(at)
      end

      it "記事が判定済みなら、その合計点の段で作る。判定に失敗した記事なら一番下の段" do
        judged = create(:article_judgment, **scores_for(rare)).article
        failed = create(:article_judgment, :failed).article

        expect(Reading.open!(judged, at: at).tier).to eq(rare)
        expect(Reading.open!(failed, at: at).tier).to eq(Dopamine.base_rarity[:name])
      end
    end

    it "判定を積めない環境（設定か API キーが無い）では、待っても届かないので一番下の段で作る" do
      expect(Reading.open!(create(:article), at: at).tier).to eq(Dopamine.base_rarity[:name])
    end

    it "未完の行があれば、枠を変えずに開き直す" do
      reading = create(:reading, tier: rare, opened_at: at - 1.hour, returned_at: at - 1.hour + 5.seconds)

      expect(Reading.open!(reading.article, at: at)).to eq(reading)
      expect(reading.reload.tier).to eq(rare)
      expect(reading.reload.opened_at).to eq(at)
      expect(reading.returned_at).to be_nil
    end

    it "判定中のまま残った行を開き直すと、届いていた判定の段を書く。判定を積めない環境になっていたら一番下の段" do
      judged = create(:reading, :pending, opened_at: at - 1.hour)
      create(:article_judgment, article: judged.article, **scores_for(rare))
      stranded = create(:reading, :pending, :completed)

      expect(Reading.open!(judged.article, at: at).tier).to eq(rare)
      expect(Reading.open!(stranded.article, at: at).tier).to eq(Dopamine.base_rarity[:name])
      expect(stranded.reload.completed_at).to be_present
    end

    it "完読済みの行は変えない" do
      reading = create(:reading, :completed)
      before = reading.attributes
      expect(Reading.open!(reading.article, at: at).attributes).to eq(before)
    end

    it "同時に作られて一意制約で落ちたら、先に入った行を返す" do
      article = create(:article)
      existing = create(:reading, article: article, tier: rare, opened_at: at - 1.minute)
      ghost = Reading.new(article: article)
      allow(Reading).to receive(:find_or_initialize_by).and_return(ghost)
      allow(ghost).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique.new("二重タップ"))

      expect(Reading.open!(article, at: at)).to eq(existing)
    end
  end

  describe ".settle_tier!" do
    let(:rare) { Dopamine.rarity_names.second }

    it "判定中の行に、記事の判定の合計点の段を書いて返す" do
      reading = create(:reading, :pending)
      create(:article_judgment, article: reading.article, **scores_for(rare))

      expect(Reading.settle_tier!(reading.article)).to eq(reading)
      expect(reading.reload.tier).to eq(rare)
    end

    it "判定が無い・失敗した記事は一番下の段にする" do
      unjudged = create(:reading, :pending)
      failed = create(:reading, :pending)
      create(:article_judgment, :failed, article: failed.article)

      [ unjudged, failed ].each { |reading| Reading.settle_tier!(reading.article) }

      expect([ unjudged, failed ].map { |reading| reading.reload.tier }).to all(eq(Dopamine.base_rarity[:name]))
    end

    it "一度決まった枠は動かさず、nil を返す（境界を変えても、手に入れたカードは変わらない）" do
      reading = create(:reading, tier: Dopamine.base_rarity[:name])
      create(:article_judgment, article: reading.article, **scores_for(rare))

      expect(Reading.settle_tier!(reading.article)).to be_nil
      expect(reading.reload.tier).to eq(Dopamine.base_rarity[:name])
    end

    it "読むと決めていない記事では何もしない" do
      expect(Reading.settle_tier!(create(:article))).to be_nil
    end
  end

  describe "#start!" do
    let(:at) { Time.zone.local(2026, 10, 20, 12) }

    it "判定前なら opened_at を記事を開いた時刻にする（カードを眺めていた時間は滞在に入れない）" do
      reading = create(:reading, opened_at: at - 10.minutes)

      expect(reading.start!(at: at)).to eq(reading)
      expect(reading.reload.opened_at).to eq(at)
      expect(reading.returned_at).to be_nil
    end

    it "判定済みなら未完でも何もしない（区切りの滞在を書き換えない）" do
      incomplete = create(:reading, opened_at: at - 1.minute, returned_at: at - 50.seconds)
      completed = create(:reading, :completed)

      expect { incomplete.start!(at: at) }.not_to(change { incomplete.reload.attributes })
      expect { completed.start!(at: at) }.not_to(change { completed.reload.attributes })
    end
  end
end
