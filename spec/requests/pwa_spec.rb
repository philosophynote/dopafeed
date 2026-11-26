RSpec.describe "PWA", type: :request do
  let(:fingerprinted_icon) { %r{\A/assets/icon(-180)?-\h{8,}\.(png|svg)\z} }

  describe "GET /manifest.json" do
    it "name・180 と 512 のアイコン・display standalone・start_url / を返し、アイコンは中身の指紋付きの URL で manifest の寸法どおりに取れる" do
      get pwa_manifest_path(format: :json)

      expect(response).to have_http_status(:ok)
      manifest = response.parsed_body
      expect(manifest["name"]).to eq("Dopafeed")
      expect(manifest["display"]).to eq("standalone")
      expect(manifest["start_url"]).to eq("/")
      expect(manifest["scope"]).to eq("/")
      sizes = manifest["icons"].map { |icon| icon["sizes"] }
      expect(sizes).to include("180x180", "512x512")
      manifest["icons"].each do |icon|
        expect(icon["src"]).to match(fingerprinted_icon)
        get icon["src"]
        expect(response).to have_http_status(:ok)
        expect(response.body.byteslice(16, 8).unpack("N2").join("x")).to eq(icon["sizes"]), "#{icon["src"]} の寸法が manifest と違う"
      end
    end
  end

  describe "アイコンの置き場所" do
    it "public/ に固定 URL のアイコンを置かない" do
      expect(Rails.public_path.glob("icon*")).to be_empty
    end
  end

  describe "layout" do
    it "manifest と、指紋付きの URL の favicon・180 の apple-touch-icon を link し、ログイン中だけアイコンのバッジに未読数を渡す" do
      get new_session_path
      page = Capybara.string(response.body)
      expect(page).to have_css("link[rel=manifest][href='/manifest.json']", visible: :all)
      expect(page.find("link[rel=apple-touch-icon]", visible: :all)[:href]).to match(fingerprinted_icon).and include("icon-180-")
      favicons = page.all("link[rel=icon]", visible: :all).map { |link| link[:href] }
      expect(favicons.size).to eq(2)
      expect(favicons).to all(match(fingerprinted_icon))
      expect(page).to have_no_css("#app-badge", visible: :all)

      create_list(:article, 2)
      sign_in_as(create(:user))
      get root_path
      expect(Capybara.string(response.body)).to have_css("#app-badge[data-controller=badge][data-badge-count-value='2']", visible: :all)
    end
  end

  describe "GET /service-worker" do
    # ブラウザの register は Accept: */* で取りに来る（html だと .js のテンプレートが見つからない）
    it "JavaScript を返し、activate・push・notificationclick の登録と、受信時のバッジの書き直しを含む（文字列検査。実行はしない）" do
      get pwa_service_worker_path, headers: { "Accept" => "*/*" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/javascript")
      expect(response.body).to include('addEventListener("install"', 'addEventListener("activate"', 'addEventListener("push"', 'addEventListener("notificationclick"',
                                       "showNotification(", "setAppBadge(", "clearAppBadge(", "openWindow(")
      expect(response.body[/icon: "([^"]+)"/, 1]).to match(fingerprinted_icon).and include("icon-180-")
    end
  end
end
