require "test_helper"

class ReadingTest < ActiveSupport::TestCase
  test "article, opened_at, tier が必須" do
    reading = Reading.new
    assert_not reading.valid?
    assert_includes reading.errors[:article], "must exist"
    assert_includes reading.errors[:opened_at], "can't be blank"
    assert_includes reading.errors[:tier], "is not included in the list"
  end

  test "tier は dopamine.yml の xp.tiers の name だけ" do
    article = articles(:rails_82)
    Dopamine.tier_names.each do |name|
      assert Reading.new(article: article, opened_at: Time.current, tier: name).valid?, "#{name} は有効な tier"
    end
    bogus = Reading.new(article: article, opened_at: Time.current, tier: "legendary")
    assert_not bogus.valid?
    assert_includes bogus.errors[:tier], "is not included in the list"
  end

  test "1 記事 1 行（同じ記事に 2 行目は作れない）" do
    existing = readings(:rails_81_completed)
    dup = Reading.new(article: existing.article, opened_at: Time.current, tier: existing.tier)
    assert_not dup.valid?
    assert_includes dup.errors[:article_id], "has already been taken"
  end

  test "xp は 0 以上の整数" do
    reading = readings(:rails_81_completed)
    reading.xp = -1
    assert_not reading.valid?
    reading.xp = 0
    assert reading.valid?
  end

  test "xp と combo_multiplier は開いただけなら 0 と nil" do
    reading = readings(:weekly_770_opened)
    assert_equal 0, reading.xp
    assert_nil reading.combo_multiplier
  end

  test "completed? は completed_at の有無" do
    assert readings(:rails_81_completed).completed?
    assert_not readings(:weekly_770_opened).completed?
  end

  test "dwell_seconds は戻った時刻 − 開いた時刻。戻っていなければ nil" do
    completed = readings(:rails_81_completed)
    assert_equal 4 * 60 + 12, completed.dwell_seconds
    assert_nil readings(:weekly_770_opened).dwell_seconds
  end

  test "completed スコープは completed_at のある行だけ" do
    assert_equal [ readings(:rails_81_completed) ], Reading.completed.to_a
  end

  test "on(day) は reset_hour 基準の 1 日で completed_at を絞る" do
    reset_hour = Dopamine.settings.dig(:daily_goal, :reset_hour)
    day = Date.new(2026, 10, 20)
    article_a = articles(:rails_82)
    article_b = Article.create!(feed: feeds(:ruby_weekly), title: "b", url: "https://fixtures.example.com/b")
    article_c = Article.create!(feed: feeds(:ruby_weekly), title: "c", url: "https://fixtures.example.com/c")
    article_d = Article.create!(feed: feeds(:ruby_weekly), title: "d", url: "https://fixtures.example.com/d")

    just_before = complete(article_a, at: Time.zone.local(2026, 10, 20, reset_hour) - 1.minute)
    at_start = complete(article_b, at: Time.zone.local(2026, 10, 20, reset_hour))
    last_minute = complete(article_c, at: Time.zone.local(2026, 10, 21, reset_hour) - 1.minute)
    next_day_start = complete(article_d, at: Time.zone.local(2026, 10, 21, reset_hour))

    assert_equal [ at_start, last_minute ].sort, Reading.on(day).sort
    assert_includes Reading.on(day - 1), just_before
    assert_includes Reading.on(day + 1), next_day_start, "翌日の reset_hour ちょうどは翌日分（SQL の < で切る）"
    assert_not_includes Reading.on(ReadingDay.of(readings(:weekly_770_opened).opened_at)), readings(:weekly_770_opened),
                        "completed_at が nil の行は除く"
  end

  test "fixture の完読は daily_goals の day と同じ日（Tokyo）" do
    reading = readings(:rails_81_completed)
    assert_equal daily_goals(:achieved_oct_5).day, ReadingDay.of(reading.completed_at)
    assert_includes Reading.on(daily_goals(:achieved_oct_5).day), reading
  end

  test "completed_at があるなら returned_at も要る" do
    reading = readings(:rails_81_completed)
    reading.returned_at = nil
    assert_not reading.valid?
    assert_includes reading.errors[:returned_at], "can't be blank"
  end

  private

  # 完読した Reading を 1 行作る（開いた時刻は 1 分前）
  def complete(article, at:)
    Reading.create!(article: article, tier: "common", opened_at: at - 1.minute, returned_at: at, completed_at: at)
  end
end
