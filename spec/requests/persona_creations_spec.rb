RSpec.describe "Persona の追加", type: :request do
  let(:attrs) { { name: "坂本龍馬", title: "土佐の脱藩浪士", color: "#1E40AF", description: "日本を今一度せんたく", system_prompt: "あなたは坂本龍馬だ。\n土佐弁で話せ。" } }

  def page
    Capybara.string(response.body)
  end

  it "未ログインならログイン画面へ。人物は増えない" do
    get new_persona_path
    expect(response).to redirect_to(new_session_path)

    expect { post personas_path, params: { persona: attrs } }.not_to change(Persona, :count)
    expect(response).to redirect_to(new_session_path)
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    it "一覧の「人物を足す」から開け、空の入力欄（色だけ初期値入り）と、出始めについての注記を出す" do
      get personas_path
      expect(page).to have_link("人物を足す", href: new_persona_path)

      get new_persona_path

      expect(page).to have_css("h1", text: "人物を足す")
      expect(page).to have_field("色", with: "#6B7280")
      %w[名前 肩書き ひとこと紹介 口調の指示（system_prompt）].each do |label|
        expect(page.find_field(label).value).to be_blank, label
      end
      expect(page).to have_button("保存")
      expect(page).to have_link("やめる", href: personas_path)
      expect(page).to have_text("足した人物は、これからコメントを作る記事から出ます")
      expect(page.all("input[type=text], textarea").map { |field| field[:required] }).to all(be_present)
    end

    it "保存すると有効なまま一覧の最後に足して一覧へ戻す。slug・有効 / 無効・並び順は送っても使わない" do
      seed_personas
      post personas_path, params: { persona: attrs.merge(slug: "ryoma", enabled: false, position: 3) }

      expect(response).to redirect_to(personas_path)
      persona = Persona.order(:id).last
      expect(persona).to have_attributes(attrs.merge(enabled: true))
      expect(persona.slug).to match(/\Apersona-[a-z]{8}\z/)
      expect(Persona.enabled.last).to eq(persona)

      follow_redirect!
      expect(page.all("[data-persona] h2").map(&:text).last).to eq("坂本龍馬")
      expect(page).to have_text("有効 9 人")
    end

    it "空の項目や色の形式の誤りは 422 で欄の下に赤字を出し、入れた値を残して何も足さない" do
      expect { post personas_path, params: { persona: attrs.merge(name: " ", color: "blue") } }.not_to change(Persona, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(page).to have_css("[role=alert]", text: "名前を入力してください")
      expect(page).to have_css("[role=alert]", text: "色は #RRGGBB で指定してください")
      expect(page).to have_no_css("[role=alert]", text: "肩書き")
      expect(page).to have_field("肩書き", with: "土佐の脱藩浪士")
      expect(page).to have_field("色", with: "blue")
    end
  end
end
