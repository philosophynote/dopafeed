require "test_helper"

class DopamineTest < ActiveSupport::TestCase
  test "settings は config/dopamine.yml をそのまま返す" do
    assert_equal Rails.application.config_for(:dopamine), Dopamine.settings
  end

  test "tier_names は xp.tiers の name を順に返す" do
    expected = Rails.application.config_for(:dopamine).dig(:xp, :tiers).map { |tier| tier[:name] }
    assert_equal expected, Dopamine.tier_names
    assert_not_empty Dopamine.tier_names
  end
end
