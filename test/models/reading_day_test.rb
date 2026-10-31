require "test_helper"

# 読書の「1 日」は config/dopamine.yml の daily_goal.reset_hour で切り替わる（Asia/Tokyo）。
# 時刻は yml の値から組み立てる。4 を書かない。
class ReadingDayTest < ActiveSupport::TestCase
  setup do
    @reset_hour = Dopamine.settings.dig(:daily_goal, :reset_hour)
  end

  test "アプリのタイムゾーンは Tokyo" do
    assert_equal "Tokyo", Time.zone.name
  end

  test "reset_hour の 1 分前は前日として数える" do
    time = Time.zone.local(2026, 10, 20, @reset_hour) - 1.minute
    assert_equal Date.new(2026, 10, 19), ReadingDay.of(time)
  end

  test "reset_hour ちょうどは当日として数える" do
    time = Time.zone.local(2026, 10, 20, @reset_hour)
    assert_equal Date.new(2026, 10, 20), ReadingDay.of(time)
  end

  test "引数なしは現在時刻" do
    travel_to Time.zone.local(2026, 10, 20, @reset_hour) + 10.hours do
      assert_equal Date.new(2026, 10, 20), ReadingDay.of
    end
  end

  test "UTC で渡しても Tokyo の reset_hour で切る" do
    tokyo = Time.zone.local(2026, 10, 20, @reset_hour) - 1.minute
    assert_equal Date.new(2026, 10, 19), ReadingDay.of(tokyo.utc)
  end

  test "range は reset_hour から翌日の reset_hour 手前まで" do
    range = ReadingDay.range(Date.new(2026, 10, 20))
    assert_equal Time.zone.local(2026, 10, 20, @reset_hour), range.begin
    assert_equal Time.zone.local(2026, 10, 21, @reset_hour), range.end
    assert range.exclude_end?, "翌日の reset_hour ちょうどは翌日分"
  end

  test "of と range は互いに整合する" do
    day = Date.new(2026, 10, 20)
    range = ReadingDay.range(day)
    assert_equal day, ReadingDay.of(range.begin)
    assert_equal day, ReadingDay.of(range.end - 1.second)
    assert_equal day + 1, ReadingDay.of(range.end)
  end
end
