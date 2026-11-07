# VAPID の鍵は ENV（docs/decisions/0013）。無ければ購読を受け付けず、画面は「鍵が無い」を出す
RSpec.describe Push::Vapid do
  let(:keys) { { "VAPID_PUBLIC_KEY" => "BPublic", "VAPID_PRIVATE_KEY" => "private", "VAPID_SUBJECT" => "mailto:nao@example.com" } }

  it "3 つ揃っていれば configured?、公開鍵を返す" do
    with_env(keys) do
      expect(described_class).to be_configured
      expect(described_class.public_key).to eq("BPublic")
      expect(described_class.private_key).to eq("private")
      expect(described_class.subject).to eq("mailto:nao@example.com")
    end
  end

  it "どれか 1 つでも無ければ configured? は偽で、public_key は nil" do
    keys.each_key do |missing|
      with_env(keys.merge(missing => nil)) do
        expect(described_class).not_to be_configured
        expect(described_class.public_key).to be_nil
      end
    end
  end
end
