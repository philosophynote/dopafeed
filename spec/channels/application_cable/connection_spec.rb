RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:user) { create(:user) }
  let(:session) { user.sessions.create! }

  it "期限内の Session の cookie なら、そのユーザーで繋がる" do
    cookies.signed[:session_id] = session.id

    connect "/cable"

    expect(connection.current_user).to eq(user)
  end

  it "最後に使ってから保つ期間を過ぎた Session の cookie は拒む" do
    session.update_column(:updated_at, (Session::REMEMBER_FOR + 1.day).ago)
    cookies.signed[:session_id] = session.id

    expect { connect "/cable" }.to have_rejected_connection
  end

  it "cookie が無ければ拒む" do
    expect { connect "/cable" }.to have_rejected_connection
  end
end
