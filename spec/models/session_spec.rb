RSpec.describe Session do
  describe ".unexpired" do
    let(:user) { create(:user) }

    it "最後に使ってから保つ期間の内の行だけを返す" do
      fresh = user.sessions.create!
      stale = user.sessions.create!
      stale.update_column(:updated_at, (Session::REMEMBER_FOR + 1.minute).ago)

      expect(Session.unexpired).to contain_exactly(fresh)
    end
  end
end
