RSpec.describe User, type: :model do
  it "email_address を小文字にし、前後の空白を除く" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    expect(user.email_address).to eq("downcased@example.com")
  end
end
