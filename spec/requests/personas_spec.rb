RSpec.describe "Personas", type: :request do
  let(:comments) { Dopamine.settings[:comments].merge(personas_shown: 3) }

  before { allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.merge(comments: comments)) }

  def page
    Capybara.string(response.body)
  end

  def switch_of(name)
    page.find("[role=switch][aria-label='#{name}をコメントに出す']")
  end

  it "未ログインならログイン画面へ。人物は変わらない" do
    persona = create(:persona)

    get personas_path
    expect(response).to redirect_to(new_session_path)

    patch persona_enablement_path(persona), params: { enabled: false }
    expect(response).to redirect_to(new_session_path)
    expect(persona.reload.enabled).to be(true)
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    it "人物を並び順で、名前・肩書き・ひとこと紹介・オンのスイッチつきで出し、有効な人数を案内する" do
      seed_personas

      get personas_path

      expect(page).to have_css("h1", text: "コメントの人物")
      expect(page).to have_link("戻る", href: learning_path)
      expect(page.all("[data-persona]").map { |row| row.find("h2").text }).to eq(Persona.ordered.map(&:name))
      expect(switch_of("織田信長")["aria-checked"]).to eq("true")
      expect(page).to have_text("戦国大名")
      expect(page).to have_text("古い慣習を嫌い、良い新技術はすぐ取り入れる革新家")
      expect(page).to have_text("有効 8 人。コメントでは 8 人の中から 3 人が出ます")
      expect(page).to have_text("外した人物のコメントは消えません。戻すと過去の記事でもまた出ます")
    end

    it "無効の人はスイッチがオフ。有効が personas_shown 未満なら全員が出ると、0 人なら欄が出ないと案内する" do
      create(:persona, name: "出る人")
      off = create(:persona, name: "外した人", enabled: false)
      create(:persona, name: "もう一人")

      get personas_path
      expect(switch_of("外した人")["aria-checked"]).to eq("false")
      expect(page).to have_text("有効 2 人。コメントでは 2 人全員が出ます")

      Persona.where.not(id: off.id).update_all(enabled: false)
      get personas_path
      expect(page).to have_text("有効な人物がいないので、記事にコメントの欄は出ません")
    end

    it "スイッチを押すと enabled だけを変え、その行と人数の案内を Turbo Stream で差し替える" do
      persona = create(:persona, name: "織田信長")
      create(:persona)

      patch persona_enablement_path(persona), params: { enabled: false, persona: { name: "書き換え", system_prompt: "x" } }, as: :turbo_stream

      expect(persona.reload).to have_attributes(enabled: false, name: "織田信長")
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(%(target="#{ActionView::RecordIdentifier.dom_id(persona)}"), %(target="personas_summary"))
      expect(response.body).to include(%(aria-checked="false"), "有効 1 人")

      patch persona_enablement_path(persona), params: { enabled: true }, as: :turbo_stream
      expect(persona.reload.enabled).to be(true)
    end

    it "JS が無いときは送信後に一覧へ戻す" do
      persona = create(:persona)

      patch persona_enablement_path(persona), params: { enabled: false }

      expect(response).to redirect_to(personas_path)
      expect(persona.reload.enabled).to be(false)
    end

    it "無い人物は 404" do
      patch persona_enablement_path(persona_id: 0), params: { enabled: false }
      expect(response).to have_http_status(:not_found)
    end

    it "設定に「コメントの人物」の行がある" do
      get learning_path
      expect(page).to have_link("コメントの人物", href: personas_path)
    end
  end
end
