require "test_helper"

# db/seeds.rb は bin/setup と CI の「Tests: Seeds」段で毎回走る。冪等でなければならない
class SeedsTest < ActiveSupport::TestCase
  setup do
    Article.delete_all
    Feed.delete_all
    Session.delete_all
    User.delete_all
  end

  test "5 フィード・30 記事・1 ユーザーが入り、二度流しても増えない" do
    2.times { Rails.application.load_seed }

    assert_equal 5, Feed.count
    assert_equal 30, Article.count
    assert_equal 1, User.count
    assert Feed.all.all? { |feed| feed.articles.count == 6 }, "各フィードに 6 本ずつ"
    assert Article.where(summary: [ nil, "" ]).none?, "seed の記事は全部要約つき"
  end

  test "ユーザーは ENV の email / password で作られる" do
    with_env("DOPAFEED_USER_EMAIL" => "env@example.com", "DOPAFEED_USER_PASSWORD" => "from-env-pass") do
      Rails.application.load_seed
    end

    user = User.sole
    assert_equal "env@example.com", user.email_address
    assert user.authenticate("from-env-pass")
  end

  test "既存ユーザーのパスワードは上書きしない" do
    User.create!(email_address: "nao@example.com", password: "already-set")

    Rails.application.load_seed

    assert User.sole.authenticate("already-set")
  end

  test "production では ENV のユーザーだけを作り、example.com の記事やフィードは入れない" do
    with_env("DOPAFEED_USER_EMAIL" => "prod@example.com", "DOPAFEED_USER_PASSWORD" => "prod-pass") do
      pretending_production { Rails.application.load_seed }
    end

    assert_equal 1, User.count
    assert User.sole.authenticate("prod-pass")
    assert_equal 0, Feed.count
    assert_equal 0, Article.count
  end

  test "production で ENV が無ければ止まる（既定パスワードのユーザーを作らない）" do
    with_env("DOPAFEED_USER_EMAIL" => nil, "DOPAFEED_USER_PASSWORD" => nil) do
      pretending_production do
        assert_raises(KeyError) { Rails.application.load_seed }
      end
    end
    assert_equal 0, User.count
  end

  private

  # Rails.env だけを差し替える。DB 接続は test のまま（seed は Rails.env.production? しか見ない）
  def pretending_production
    original = Rails.env
    Rails.env = "production"
    yield
  ensure
    Rails.env = original
  end

  def with_env(values)
    saved = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
