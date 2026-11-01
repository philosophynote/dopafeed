# db/seeds.rb は bin/setup と CI の「Tests: Seeds」段で毎回走る。冪等でなければならない
RSpec.describe "db/seeds.rb" do
  before do
    Article.delete_all
    Feed.delete_all
    Session.delete_all
    User.delete_all
  end

  it "5 フィード・30 記事・1 ユーザーが入り、二度流しても増えない" do
    2.times { Rails.application.load_seed }

    expect(Feed.count).to eq(5)
    expect(Article.count).to eq(30)
    expect(User.count).to eq(1)
    expect(Feed.all).to all(satisfy("各フィードに 6 本ずつ") { |feed| feed.articles.count == 6 })
    expect(Article.where(summary: [ nil, "" ])).to be_none, "seed の記事は全部要約つき"
  end

  it "ユーザーは ENV の email / password で作られる" do
    with_env("DOPAFEED_USER_EMAIL" => "env@example.com", "DOPAFEED_USER_PASSWORD" => "from-env-pass") do
      Rails.application.load_seed
    end

    user = User.sole
    expect(user.email_address).to eq("env@example.com")
    expect(user.authenticate("from-env-pass")).to be_truthy
  end

  it "既存ユーザーのパスワードは上書きしない" do
    User.create!(email_address: "nao@example.com", password: "already-set")

    Rails.application.load_seed

    expect(User.sole.authenticate("already-set")).to be_truthy
  end

  it "production では ENV のユーザーだけを作り、example.com の記事やフィードは入れない" do
    with_env("DOPAFEED_USER_EMAIL" => "prod@example.com", "DOPAFEED_USER_PASSWORD" => "prod-pass") do
      pretending_production { Rails.application.load_seed }
    end

    expect(User.count).to eq(1)
    expect(User.sole.authenticate("prod-pass")).to be_truthy
    expect(Feed.count).to eq(0)
    expect(Article.count).to eq(0)
  end

  it "production で ENV が無ければ止まる（既定パスワードのユーザーを作らない）" do
    with_env("DOPAFEED_USER_EMAIL" => nil, "DOPAFEED_USER_PASSWORD" => nil) do
      pretending_production do
        expect { Rails.application.load_seed }.to raise_error(KeyError)
      end
    end
    expect(User.count).to eq(0)
  end
end
