require "test_helper"

module Claude
  class ClientTest < ActiveSupport::TestCase
    test "ANTHROPIC_API_KEY が無ければ KeyError で止まる（黙って空キーで呼ばない）" do
      with_env("ANTHROPIC_API_KEY" => nil) do
        assert_raises(KeyError) { Client.build }
      end
    end

    test "ANTHROPIC_API_KEY があれば SDK のクライアントを返す" do
      with_env("ANTHROPIC_API_KEY" => "test-key") do
        assert_kind_of Anthropic::Client, Client.build
      end
    end

    private

    def with_env(values)
      saved = values.keys.index_with { |key| ENV[key] }
      values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      yield
    ensure
      saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end
end
