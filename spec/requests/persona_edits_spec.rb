RSpec.describe "Persona の書き換え", type: :request do
  let(:persona) { create(:persona, name: "織田信長", title: "戦国大名", color: "#C8102E", description: "革新家", system_prompt: "あなたは織田信長だ。") }
  let(:attrs) { { name: "第六天魔王", title: "尾張の大名", color: "#112233", description: "旧弊を嫌う", system_prompt: "あなたは信長だ。\n短く斬れ。" } }

  def page
    Capybara.string(response.body)
  end

  it "未ログインならログイン画面へ。人物は変わらない" do
    get edit_persona_path(persona)
    expect(response).to redirect_to(new_session_path)

    patch persona_path(persona), params: { persona: attrs }
    expect(response).to redirect_to(new_session_path)
    expect(persona.reload.name).to eq("織田信長")
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    it "一覧の行の ⋯ から開ける。今の値入りの入力欄と、保存済みのコメントは作り直さない旨の注記を出す" do
      persona
      get personas_path
      expect(page.find("[data-persona] details")).to have_link("変更", href: edit_persona_path(persona), visible: :all)

      get edit_persona_path(persona)

      expect(page).to have_field("名前", with: "織田信長")
      expect(page).to have_field("肩書き", with: "戦国大名")
      expect(page).to have_field("色", type: "color", with: "#c8102e")
      expect(page).to have_field("ひとこと紹介", with: "革新家")
      expect(page).to have_field("口調の指示（system_prompt）", with: "あなたは織田信長だ。")
      expect(page).to have_button("保存")
      expect(page).to have_link("やめる", href: personas_path)
      expect(page).to have_text("保存済みのコメントは作り直しません。書き換えは、これからコメントを作る記事から効きます")
      expect(page.all("input[type=text], textarea").map { |field| field[:required] }).to all(be_present)
    end

    it "保存すると 5 つを書き換えて一覧へ戻す。前後の空白は落とし、slug と有効 / 無効は変えない" do
      slug = persona.slug
      patch persona_path(persona), params: { persona: attrs.merge(name: "  第六天魔王 ", slug: "maou", enabled: false) }

      expect(response).to redirect_to(personas_path)
      expect(persona.reload).to have_attributes(attrs.merge(slug: slug, enabled: true))
    end

    it "空の項目や色の形式の誤りは 422 で欄の下に赤字を出し、何も変えない" do
      patch persona_path(persona), params: { persona: attrs.merge(name: " ", system_prompt: "", color: "red") }

      expect(response).to have_http_status(:unprocessable_content)
      expect(page).to have_css("[role=alert]", text: "名前を入力してください")
      expect(page).to have_css("[role=alert]", text: "口調の指示を入力してください")
      expect(page).to have_css("[role=alert]", text: "色は #RRGGBB で指定してください")
      expect(page).to have_no_css("[role=alert]", text: "肩書き")
      expect(persona.reload.name).to eq("織田信長")
    end

    it "保存済みのコメントは書き換えても変わらない" do
      comment = create(:article).persona_comments.create!(persona_id: persona.slug, body: "前の口調のひとこと")

      patch persona_path(persona), params: { persona: attrs }

      expect(comment.reload).to have_attributes(persona_id: persona.slug, body: "前の口調のひとこと")
      expect(comment.persona.name).to eq("第六天魔王")
    end

    it "書き換えた口調の指示は、次に作るコメントの指示に入る" do
      patch persona_path(persona), params: { persona: attrs }

      instructions = Comments::Commenter.new(build(:article), persona.reload).send(:system_prompt)
      expect(instructions).to include("あなたは信長だ。\n短く斬れ。")
      expect(instructions).not_to include("あなたは織田信長だ。")
    end

    it "無い人物は 404" do
      get edit_persona_path(id: 0)
      expect(response).to have_http_status(:not_found)
    end
  end
end
