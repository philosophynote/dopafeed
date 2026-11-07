# PWA の配信物（docs/screens/install.md の manifest / service worker の受け入れ条件）。
# ホーム画面に追加する前に読まれるので、ログイン無しで返る
RSpec.describe "PWA", type: :request do
  describe "GET /manifest.json" do
    it "name・180 と 512 のアイコン・display standalone・start_url / を返す（アイコンは public/ に実在する）" do
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
        expect(png_size(icon["src"])).to eq(icon["sizes"]), "#{icon["src"]} の寸法が manifest と違う"
      end
    end

    # PNG の IHDR（先頭 16 バイト目から幅・高さが 4 バイトずつ）。gem を足さずに寸法を読む
    def png_size(src)
      bytes = Rails.public_path.join(src.delete_prefix("/")).binread(24)
      bytes[16, 8].unpack("N2").join("x")
    end
  end

  describe "layout" do
    it "manifest と 180 の apple-touch-icon を link し、ログイン中だけアイコンのバッジに未読数を渡す" do
      get new_session_path
      page = Capybara.string(response.body)
      expect(page).to have_css("link[rel=manifest][href='/manifest.json']", visible: :all)
      expect(page).to have_css("link[rel=apple-touch-icon][href='/icon-180.png']", visible: :all)
      expect(page).to have_no_css("#app-badge", visible: :all)

      create_list(:article, 2)
      sign_in_as(create(:user))
      get root_path
      expect(Capybara.string(response.body)).to have_css("#app-badge[data-controller=badge][data-badge-count-value='2']", visible: :all)
    end
  end

  describe "GET /service-worker" do
    # ブラウザの register は Accept: */* で取りに来る（html だと .js のテンプレートが見つからない）
    it "JavaScript を返し、activate の登録を含む" do
      get pwa_service_worker_path, headers: { "Accept" => "*/*" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/javascript")
      expect(response.body).to include('addEventListener("install"', 'addEventListener("activate"')
    end
  end
end
