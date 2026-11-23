RSpec.describe "Comments", type: :request do
  let(:comments) { { personas_shown: 3, model: "grok-4.3", max_tokens: 4000, timeout_seconds: 60 } }
  let(:article) { create(:article, :awaiting_summary, :opened) }
  let(:names) { Persona.enabled.map(&:name) }

  before do
    seed_personas
    allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.merge(comments: comments))
  end

  def page
    Capybara.string(response.body)
  end

  def save_all(article)
    Persona.enabled.each { |persona| article.persona_comments.create!(persona_id: persona.slug, body: "#{persona.name}のひとこと") }
  end

  def shown_names
    page.all("[data-persona-id]").map { |card| card["data-persona-id"] }
  end

  it "未ログインならログイン画面へ" do
    get article_comments_path(article)
    expect(response).to redirect_to(new_session_path)

    post article_comments_path(article)
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

    it "押すと Job を 1 回だけ積み、頼んだ時刻を残して前の失敗を消し、「考え中」と購読を返す" do
      article.update!(comments_failed_at: 1.hour.ago, comments_error: "応答の形式が不正")

      freeze_time do
        post article_comments_path(article), as: :turbo_stream
        expect(article.reload).to have_attributes(comments_requested_at: Time.current, comments_failed_at: nil, comments_error: nil)
      end
      expect(Comments::CommentArticleJob).to have_been_enqueued.with(article).once
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("考え中", "turbo-cable-stream-source")
    end

    it "保存済みなら積まずに 3 人を返す（1 記事 1 回）" do
      save_all(article)

      post article_comments_path(article), as: :turbo_stream

      expect(Comments::CommentArticleJob).not_to have_been_enqueued
      expect(response.body.scan("data-persona-id=").size).to eq(3)
    end

    it "今日の上限に達していたら積まずに「今日はもう口を出せません」" do
      allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true))

      post article_comments_path(article), as: :turbo_stream

      expect(Comments::CommentArticleJob).not_to have_been_enqueued
      expect(response.body).to include("今日はもう口を出せません")
    end

    it "Job を積めなかったら頼んだ印を残さず、失敗として「もう一度」を出す（待ち続けない）" do
      allow(Comments::CommentArticleJob).to receive(:perform_later).and_return(false)

      post article_comments_path(article), as: :turbo_stream

      expect(article.reload).to have_attributes(comments_requested_at: nil, comments_error: "Job を積めなかった")
      expect(article.comments_failed_at).to be_present
      expect(response.body).to include("口を出せませんでした", "もう一度")
    end

    it "Job の中で上限に達して知らせを取りこぼしても、取り直すと「今日はもう口を出せません」" do
      allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true))

      get article_comments_path(article)

      expect(page).to have_text("今日はもう口を出せません")
      expect(page).to have_no_button("コメントを見る")
    end

    it "前の失敗が残っていても、今日の上限に達していれば「もう一度」ではなく上限を出す" do
      article.update!(comments_failed_at: 1.hour.ago, comments_error: "応答の形式が不正")
      allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true))

      get article_comments_path(article)

      expect(page).to have_text("今日はもう口を出せません")
      expect(page).to have_no_button("もう一度")
    end

    it "頼んだ Job が走っている間は、その Job が最後の 1 回を使って上限に達しても「考え中」のまま" do
      article.update!(comments_requested_at: Time.current)
      allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true))

      get article_comments_path(article)

      expect(page).to have_text("考え中")
    end

    it "JS が無いときは積んだ後にコメントの画面へ戻す" do
      post article_comments_path(article)

      expect(response).to redirect_to(article_comments_path(article))
      expect(Comments::CommentArticleJob).to have_been_enqueued.once
    end

    it "頼んだ後でまだ無ければ「考え中」、失敗していれば「口を出せませんでした」と「もう一度」" do
      article.update!(comments_requested_at: Time.current)
      get article_comments_path(article)
      expect(page).to have_text("考え中")
      expect(page).to have_no_button("コメントを見る")

      article.update!(comments_failed_at: Time.current, comments_error: "応答の形式が不正")
      get article_comments_path(article)
      expect(page).to have_text("口を出せませんでした")
      expect(page).to have_button("もう一度")
    end

    it "保存済みなら全員から 3 人を名前・肩書き・AI・本文つきで出し、注記も出す" do
      save_all(article)

      get article_comments_path(article)

      expect(shown_names.size).to eq(3)
      expect(shown_names.uniq.size).to eq(3)
      card = page.first("[data-persona-id]")
      persona = Persona.find_by!(slug: card["data-persona-id"])
      expect(card).to have_text(persona.name)
      expect(card).to have_text(persona.title)
      expect(card).to have_text("AI")
      expect(card).to have_text("#{persona.name}のひとこと")
      expect(page).to have_link("別の 3 人を見る")
      expect(page).to have_text("人物は AI による架空のキャラクターです")
    end

    it "「別の 2 人を見る」は直前の 2 人を除いた残りから選ぶ（API は呼ばない）" do
      comments[:personas_shown] = 2
      save_all(article)
      get article_comments_path(article)
      before = shown_names

      10.times do
        get page.find_link("別の 2 人を見る")[:href]
        expect(shown_names & before).to be_empty
        expect(shown_names.size).to eq(2)
        before = shown_names
      end
      expect(Comments::CommentArticleJob).not_to have_been_enqueued
    end

    it "無効にした人のコメントは出さず、有効に戻せば保存済みのコメントがまた出る" do
      save_all(article)
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

    it "外した人のコメントしか無ければ、未生成と同じく「コメントを見る」を出す（空の組を出さない）" do
      article.persona_comments.create!(persona_id: "oda-nobunaga", body: "外した人の分")
      Persona.find_by!(slug: "oda-nobunaga").update!(enabled: false)

      get article_comments_path(article)

      expect(page).to have_button("コメントを見る")
      expect(shown_names).to be_empty

      expect { post article_comments_path(article) }.to have_enqueued_job(Comments::CommentArticleJob).with(article)
      expect(article.reload.comments_requested_at).to be_present
    end

    it "有効な人物が一人もいなければ 404 で Job も積まない（鍵の欠けと同じく欄も出さない）" do
      Persona.update_all(enabled: false)

      get article_comments_path(article)
      expect(response).to have_http_status(:not_found)
      expect { post article_comments_path(article) }.not_to have_enqueued_job(Comments::CommentArticleJob)
      expect(response).to have_http_status(:not_found)
    end

    it "AI の本文は HTML として解釈せず文字として出す" do
      save_all(article)
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
      expect(Comments::CommentArticleJob).not_to have_been_enqueued
    end
  end
end
