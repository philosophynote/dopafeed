RSpec.describe "Comments", type: :request do
  let(:comments) { { personas_shown: 3, model: "grok-4.3", max_tokens: 4000, timeout_seconds: 60 } }
  let(:article) { create(:article, :awaiting_summary, :opened) }

  before do
    seed_personas
    allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.merge(comments: comments))
  end

  # turbo-stream の応答は中身が template に入り、そのままでは要素として探せない
  def page
    Capybara.string(response.body.gsub(%r{</?template>}, ""))
  end

  def save(article, slugs = Persona.enabled.map(&:slug))
    slugs.each { |slug| article.persona_comments.create!(persona_id: slug, body: "#{Persona.find_by!(slug:).name}のひとこと") }
  end

  def shown_names
    page.all("[data-persona-id]").map { |card| card["data-persona-id"] }
  end

  def enqueued_slugs
    enqueued_jobs.select { |job| job["job_class"] == "Comments::CommentPersonaJob" }
                 .map { |job| GlobalID::Locator.locate(job["arguments"].first["_aj_globalid"]).persona_id }
  end

  it "未ログインならログイン画面へ" do
    get article_comments_path(article)
    expect(response).to redirect_to(new_session_path)

    post article_comments_path(article)
    expect(response).to redirect_to(new_session_path)

    post retry_article_comments_path(article)
    expect(response).to redirect_to(new_session_path)
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    it "未生成なら「? ? ?」と人数の案内と「コメントを見る」、注記を出す" do
      get article_comments_path(article)

      expect(page).to have_text("? ? ?")
      expect(page).to have_text("この記事に、誰が口を出すか")
      expect(page).to have_text("#{Persona.enabled.count} 人の中から 3 人がランダムに現れます")
      expect(page).to have_button("コメントを見る")
      expect(page).to have_text("人物は AI による架空のキャラクターです。本人の発言ではありません")
    end

    it "押すと有効な人から 3 人を選んで書いている途中の行を作り、1 人 1 本ずつ Job を積み、3 人のカードと購読を返す" do
      post article_comments_path(article), as: :turbo_stream

      rows = article.persona_comments.to_a
      expect(rows.size).to eq(3)
      expect(rows.map(&:state)).to all(eq(:writing))
      expect(enqueued_slugs).to match_array(rows.map(&:persona_id))
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(shown_names).to match_array(rows.map(&:persona_id))
      expect(response.body.scan("書いています").size).to eq(3)
      expect(response.body).to include("turbo-cable-stream-source")
    end

    it "読み直しても、書いている途中の人の枠を同じ顔ぶれで出す" do
      post article_comments_path(article)
      slugs = article.persona_comments.pluck(:persona_id)

      get article_comments_path(article)

      expect(shown_names).to match_array(slugs)
      expect(page).to have_css("li[data-state='writing']", count: 3)
    end

    it "有効な全員が作成済みなら積まずに 3 人を返す（記事 × 人物で 1 回）" do
      save(article)

      post article_comments_path(article), as: :turbo_stream

      expect(enqueued_slugs).to be_empty
      expect(response.body.scan("data-persona-id=").size).to eq(3)
    end

    it "「別の 3 人を見る」は直前の組を除き、まだ作っていない人から作る。全員そろえば API を呼ばず組み替える" do
      post article_comments_path(article)
      first = article.persona_comments.pluck(:persona_id)
      article.persona_comments.update_all(body: "書けた")
      clear_enqueued_jobs

      post article_comments_path(article, except: first.join(",")), as: :turbo_stream
      second = enqueued_slugs
      expect(second.size).to eq(3)
      expect(second & first).to be_empty
      expect(shown_names).to match_array(second)
      article.persona_comments.update_all(body: "書けた")
      clear_enqueued_jobs

      post article_comments_path(article, except: second.join(",")), as: :turbo_stream
      third = enqueued_slugs
      expect(third).to match_array(Persona.enabled.map(&:slug) - first - second)
      expect(shown_names.size).to eq(3)
      expect(shown_names).to include(*third)
      expect(shown_names & second).to be_empty
      article.persona_comments.update_all(body: "書けた")
      clear_enqueued_jobs

      post article_comments_path(article, except: shown_names.join(",")), as: :turbo_stream
      expect(enqueued_slugs).to be_empty
      expect(shown_names.size).to eq(3)
    end

    it "後から有効にした人は、コメントのある記事でも次に押したときに作る" do
      Persona.find_by!(slug: "margaret-thatcher").update!(enabled: false)
      save(article, Persona.enabled.map(&:slug))
      Persona.find_by!(slug: "margaret-thatcher").update!(enabled: true)

      post article_comments_path(article), as: :turbo_stream

      expect(enqueued_slugs).to eq([ "margaret-thatcher" ])
      expect(shown_names.size).to eq(3)
      expect(shown_names).to include("margaret-thatcher")
    end

    it "失敗した人は「口を出せませんでした」と「もう一度」。押すとその人だけ書いている途中に戻して積み直す" do
      save(article, %w[oda-nobunaga joseph-stalin])
      failed = article.persona_comments.create!(persona_id: "mao-zedong", failed_at: Time.current, error: "応答の形式が不正")

      get article_comments_path(article)
      card = page.find("[data-persona-id='mao-zedong']")
      expect(card).to have_text("口を出せませんでした")
      expect(card).to have_button("もう一度")
      expect(page.find("[data-persona-id='oda-nobunaga']")).to have_text("織田信長のひとこと")

      post retry_article_comments_path(article, persona_comment_id: failed.id), as: :turbo_stream

      expect(failed.reload).to have_attributes(state: :writing, error: nil)
      expect(enqueued_slugs).to eq([ "mao-zedong" ])
      expect(response.body).to include("replace", ActionView::RecordIdentifier.dom_id(failed), "書いています")
    end

    it "失敗していない行の「もう一度」は積まない（書いている途中・書き上がりを二重に払わない）" do
      writing = article.persona_comments.create!(persona_id: "oda-nobunaga")
      written = article.persona_comments.create!(persona_id: "joseph-stalin", body: "書けた")

      post retry_article_comments_path(article, persona_comment_id: writing.id), as: :turbo_stream
      post retry_article_comments_path(article, persona_comment_id: written.id), as: :turbo_stream

      expect(enqueued_slugs).to be_empty
      expect(written.reload.body).to eq("書けた")
    end

    it "失敗した人のカードは、今日の上限に達していれば「もう一度」ではなく上限を出し、押されても積まない" do
      failed = article.persona_comments.create!(persona_id: "mao-zedong", failed_at: Time.current, error: "今日の上限")
      allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true))

      get article_comments_path(article)
      expect(page.find("[data-persona-id='mao-zedong']")).to have_text("今日はもう口を出せません")
      expect(page).to have_no_button("もう一度")

      post retry_article_comments_path(article, persona_comment_id: failed.id), as: :turbo_stream
      expect(enqueued_slugs).to be_empty
      expect(failed.reload.state).to eq(:failed)
    end

    it "今日の上限に達していたら行も Job も作らずに「今日はもう口を出せません」" do
      allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true))

      post article_comments_path(article), as: :turbo_stream

      expect(enqueued_slugs).to be_empty
      expect(article.persona_comments).to be_empty
      expect(response.body).to include("今日はもう口を出せません")
    end

    it "Job を積めなかった人は失敗にして「もう一度」を出す（書いている途中で待ち続けない）" do
      allow(Comments::CommentPersonaJob).to receive(:perform_later).and_return(false)

      post article_comments_path(article), as: :turbo_stream

      expect(article.persona_comments.map(&:state)).to all(eq(:failed))
      expect(article.persona_comments.pluck(:error).uniq).to eq([ "Job を積めなかった" ])
      expect(response.body).to include("口を出せませんでした", "もう一度")
    end

    it "未生成で今日の上限に達していれば、取り直しても「今日はもう口を出せません」でボタンを出さない" do
      allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true))

      get article_comments_path(article)

      expect(page).to have_text("今日はもう口を出せません")
      expect(page).to have_no_button("コメントを見る")
    end

    it "書いている途中の人は、その Job が最後の 1 回を使って上限に達しても「書いています」のまま" do
      article.persona_comments.create!(persona_id: "oda-nobunaga")
      allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true))

      get article_comments_path(article)

      expect(page.find("[data-persona-id='oda-nobunaga']")).to have_text("書いています")
    end

    it "JS が無いときは積んだ後にコメントの画面へ戻す" do
      post article_comments_path(article)

      expect(response).to redirect_to(article_comments_path(article))
      expect(enqueued_slugs.size).to eq(3)
    end

    it "書き上がった人は名前・肩書き・AI・本文つきで出し、注記も出す" do
      save(article)

      get article_comments_path(article)

      expect(shown_names.size).to eq(3)
      expect(shown_names.uniq.size).to eq(3)
      card = page.first("[data-persona-id]")
      persona = Persona.find_by!(slug: card["data-persona-id"])
      expect(card).to have_text(persona.name)
      expect(card).to have_text(persona.title)
      expect(card).to have_text("AI")
      expect(card).to have_text("#{persona.name}のひとこと")
      expect(page).to have_button("別の 3 人を見る")
      expect(page).to have_text("人物は AI による架空のキャラクターです")
    end

    it "全員そろった記事の「別の 2 人を見る」は直前の 2 人を除いた残りから選ぶ（API は呼ばない）" do
      comments[:personas_shown] = 2
      save(article)
      get article_comments_path(article)
      before = shown_names

      10.times do
        get article_comments_path(article, except: before.join(","))
        expect(shown_names & before).to be_empty
        expect(shown_names.size).to eq(2)
        before = shown_names
      end
      expect(enqueued_slugs).to be_empty
    end

    it "無効にした人のコメントは出さず、有効に戻せば保存済みのコメントがまた出る" do
      save(article)
      Persona.where.not(slug: %w[oda-nobunaga joseph-stalin mao-zedong]).update_all(enabled: false)

      get article_comments_path(article)
      expect(shown_names).to match_array(%w[oda-nobunaga joseph-stalin mao-zedong])

      Persona.update_all(enabled: false)
      Persona.where(slug: %w[donald-trump margaret-thatcher genghis-khan]).update_all(enabled: true)
      get article_comments_path(article)
      expect(shown_names).to match_array(%w[donald-trump margaret-thatcher genghis-khan])
      expect(page).to have_text("ドナルド・J・トランプのひとこと")
    end

    it "未生成の人数の案内は有効な人数にする" do
      get article_comments_path(article)
      expect(page).to have_text("8 人の中から 3 人がランダムに現れます")
      Persona.where(slug: %w[donald-trump margaret-thatcher]).update_all(enabled: false)
      get article_comments_path(article)
      expect(page).to have_text("6 人の中から 3 人がランダムに現れます")
      Persona.where.not(slug: %w[oda-nobunaga joseph-stalin mao-zedong]).update_all(enabled: false)
      get article_comments_path(article)
      expect(page).to have_text("3 人全員が現れます")
      Persona.where(slug: "mao-zedong").update_all(enabled: false)
      get article_comments_path(article)
      expect(page).to have_text("2 人全員が現れます")
    end

    it "外した人のコメントしか無ければ、未生成と同じく「コメントを見る」を出し、押すと今の有効な人から作る" do
      article.persona_comments.create!(persona_id: "oda-nobunaga", body: "外した人の分")
      Persona.find_by!(slug: "oda-nobunaga").update!(enabled: false)

      get article_comments_path(article)

      expect(page).to have_button("コメントを見る")
      expect(shown_names).to be_empty

      post article_comments_path(article)
      expect(enqueued_slugs.size).to eq(3)
      expect(enqueued_slugs).not_to include("oda-nobunaga")
    end

    it "有効な人物が一人もいなければ 404 で Job も積まない（鍵の欠けと同じく欄も出さない）" do
      Persona.update_all(enabled: false)

      get article_comments_path(article)
      expect(response).to have_http_status(:not_found)
      post article_comments_path(article)
      expect(response).to have_http_status(:not_found)
      expect(enqueued_slugs).to be_empty
    end

    it "AI の本文は HTML として解釈せず文字として出す" do
      save(article)
      article.persona_comments.update_all(body: "<script>alert(1)</script><b>太字</b>")

      get article_comments_path(article)

      expect(response.body).not_to include("<script>alert(1)</script>")
      expect(page).to have_text("<b>太字</b>")
    end

    it "yml にコメントの鍵が無ければ 404（ボタンも出さない）" do
      comments.delete(:model)

      get article_comments_path(article)
      expect(response).to have_http_status(:not_found)
      post article_comments_path(article), as: :turbo_stream
      expect(response).to have_http_status(:not_found)
      expect(enqueued_slugs).to be_empty
    end
  end
end
