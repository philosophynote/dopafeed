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

  def stream = "#{article.to_gid_param}:comments"

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

    it "最初の「コメントを見る」を二度送っても（二つのタブなど）、2 回目は今の組を返し、行も Job も増やさない" do
      post article_comments_path(article), as: :turbo_stream
      first = shown_names

      post article_comments_path(article), as: :turbo_stream

      expect(article.persona_comments.count).to eq(3)
      expect(enqueued_slugs.size).to eq(3)
      expect(shown_names).to match_array(first)
    end

    it "前の組から押した「別の 3 人を見る」は、組がもう変わっていれば作らずに今の組を返す" do
      post article_comments_path(article)
      first = article.persona_comments.pluck(:persona_id)
      post article_comments_path(article, except: first.join(",")), as: :turbo_stream
      second = shown_names
      clear_enqueued_jobs

      post article_comments_path(article, except: first.join(",")), as: :turbo_stream

      expect(enqueued_slugs).to be_empty
      expect(article.persona_comments.count).to eq(6)
      expect(shown_names).to match_array(second)
    end

    it "組の人を外した後でも、外す前に描いた画面の「別の 3 人を見る」は古い押下にせず次の組を作る" do
      post article_comments_path(article)
      first = article.persona_comments.order(:id).pluck(:persona_id)
      article.persona_comments.update_all(body: "書けた")
      Persona.where(slug: first.first(2)).update_all(enabled: false)
      clear_enqueued_jobs

      post article_comments_path(article, except: first.join(",")), as: :turbo_stream

      expect(enqueued_slugs.size).to eq(3)
      expect(shown_names.size).to eq(3)
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

      expect { post retry_article_comments_path(article, persona_comment_id: failed.id), as: :turbo_stream }
        .to have_broadcasted_to(stream).with(a_string_including("replace", ActionView::RecordIdentifier.dom_id(failed), "書いています"))

      expect(failed.reload).to have_attributes(state: :writing, error: nil)
      expect(enqueued_slugs).to eq([ "mao-zedong" ])
    end

    it "「もう一度」はカードを応答で返さず、Job より先に購読へ送る（応答が遅れて届いても、Job が送った新しいカードを上書きしない）" do
      failed = article.persona_comments.create!(persona_id: "mao-zedong", failed_at: Time.current, error: "応答の形式が不正")
      order = []
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_wrap_original { |original, *args, **opts| order << :card; original.call(*args, **opts) }
      allow(Comments::CommentPersonaJob).to receive(:perform_later).and_wrap_original { |original, *args| order << :job; original.call(*args) }

      post retry_article_comments_path(article, persona_comment_id: failed.id), as: :turbo_stream

      expect(response).to have_http_status(:no_content)
      expect(order).to eq(%i[card job])
    end

    it "「もう一度」でカードを配れなくても、Job は積む（書いている途中のまま Job の無い枠を残さない）" do
      failed = article.persona_comments.create!(persona_id: "mao-zedong", failed_at: Time.current, error: "応答の形式が不正")
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(RuntimeError, "配れない")

      post retry_article_comments_path(article, persona_comment_id: failed.id), as: :turbo_stream

      expect(enqueued_slugs).to eq([ "mao-zedong" ])
      expect(failed.reload.state).to eq(:writing)
    end

    it "外した人の「もう一度」は積まず、失敗のまま残す（出さない人のために上限を使わない）" do
      failed = article.persona_comments.create!(persona_id: "mao-zedong", failed_at: Time.current, error: "応答の形式が不正")
      Persona.find_by!(slug: "mao-zedong").update!(enabled: false)

      post retry_article_comments_path(article, persona_comment_id: failed.id), as: :turbo_stream

      expect(enqueued_slugs).to be_empty
      expect(failed.reload.state).to eq(:failed)
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
      allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true, remaining: 0))

      get article_comments_path(article)
      expect(page.find("[data-persona-id='mao-zedong']")).to have_text("今日はもう口を出せません")
      expect(page).to have_no_button("もう一度")

      post retry_article_comments_path(article, persona_comment_id: failed.id), as: :turbo_stream
      expect(enqueued_slugs).to be_empty
      expect(failed.reload.state).to eq(:failed)
    end

    it "「別の 3 人」で一部だけ作った後に読み直しても（取り直しも普通の再読込も）押したときの組を出し、直前の組の人に入れ替えない" do
      first = %w[oda-nobunaga joseph-stalin mao-zedong]
      second = %w[shuzo-matsuoka otto-von-bismarck genghis-khan]
      save(article, first + second)

      post article_comments_path(article, except: second.join(",")), as: :turbo_stream
      shown = shown_names
      expect(shown).to include("donald-trump", "margaret-thatcher")
      refresh = page.find("[data-controller='pending-refresh']")["data-pending-refresh-url-value"]
      expect(refresh).to eq(article_comments_path(article))

      10.times do
        get article_comments_path(article)
        expect(shown_names).to eq(shown)
      end
    end

    it "書いている途中で外した人は、書き上がっても出さない（コメントは残す）" do
      save(article, %w[joseph-stalin mao-zedong])
      writing = article.persona_comments.create!(persona_id: "oda-nobunaga")
      Persona.find_by!(slug: "oda-nobunaga").update!(enabled: false)
      writing.update!(body: "外した後に書けた")

      get article_comments_path(article)

      expect(shown_names).to match_array(%w[joseph-stalin mao-zedong])
      expect(writing.reload.body).to eq("外した後に書けた")
    end

    it "今日の残りの回数が personas_shown より少なければ、残りの人数分だけ作る（上限で失敗すると分かっている枠を並べない）" do
      allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: false, remaining: 1))

      post article_comments_path(article), as: :turbo_stream

      expect(article.persona_comments.count).to eq(1)
      expect(enqueued_slugs.size).to eq(1)
    end

    it "「もう一度」で Job を積めなかったら、その人を失敗に戻す" do
      failed = article.persona_comments.create!(persona_id: "mao-zedong", failed_at: Time.current, error: "応答の形式が不正")
      allow(Comments::CommentPersonaJob).to receive(:perform_later).and_return(false)

      expect { post retry_article_comments_path(article, persona_comment_id: failed.id), as: :turbo_stream }
        .to have_broadcasted_to(stream).with(a_string_including("もう一度"))

      expect(failed.reload).to have_attributes(state: :failed, error: "Job を積めなかった")
    end

    it "別の記事のコメントは頼み直せない（404）" do
      other = create(:article).persona_comments.create!(persona_id: "mao-zedong", failed_at: Time.current, error: "x")

      post retry_article_comments_path(article, persona_comment_id: other.id), as: :turbo_stream

      expect(response).to have_http_status(:not_found)
      expect(enqueued_slugs).to be_empty
    end

    it "yml の comments.stale_after_seconds より古い書いている途中は失敗として「もう一度」を出し、押すと積み直す。鍵が無ければ書いている途中のまま" do
      stuck = article.persona_comments.create!(persona_id: "mao-zedong")
      stuck.update_columns(updated_at: 2.hours.ago)

      get article_comments_path(article)
      expect(page.find("[data-persona-id='mao-zedong']")).to have_text("書いています")

      comments[:stale_after_seconds] = 3600
      get article_comments_path(article)
      expect(page.find("[data-persona-id='mao-zedong']")).to have_button("もう一度")

      post retry_article_comments_path(article, persona_comment_id: stuck.id), as: :turbo_stream
      expect(stuck.reload.state).to eq(:writing)
      expect(enqueued_slugs).to eq([ "mao-zedong" ])
    end

    it "上限の日の「別の 3 人を見る」は、作り済みの別の人がいれば作らずに組み替える" do
      save(article, %w[oda-nobunaga joseph-stalin mao-zedong shuzo-matsuoka otto-von-bismarck genghis-khan])
      article.persona_comments.where(persona_id: %w[oda-nobunaga joseph-stalin mao-zedong]).update_all(shown_at: Time.current)
      allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true, remaining: 0))

      post article_comments_path(article, except: "oda-nobunaga,joseph-stalin,mao-zedong"), as: :turbo_stream

      expect(article.persona_comments.count).to eq(6)
      expect(shown_names).to match_array(%w[shuzo-matsuoka otto-von-bismarck genghis-khan])
      expect(page).to have_button("別の 3 人を見る")
    end

    it "上限の日の「別の 3 人を見る」で組み替える人もいなければ、同じ組のままボタンを「今日はもう口を出せません」に替える" do
      post article_comments_path(article)
      first = article.persona_comments.pluck(:persona_id)
      article.persona_comments.update_all(body: "書けた")
      allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true, remaining: 0))

      post article_comments_path(article, except: first.join(",")), as: :turbo_stream

      expect(article.persona_comments.count).to eq(3)
      expect(shown_names).to match_array(first)
      expect(page).to have_text("今日はもう口を出せません")
      expect(page).to have_no_button(/別の/)
    end

    it "上限の日の「別の 3 人を見る」は、直前の組にいない人を先に選び、足りない分だけ直前の組から補う" do
      save(article, %w[oda-nobunaga joseph-stalin mao-zedong shuzo-matsuoka])
      allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true, remaining: 0))

      5.times do
        article.persona_comments.update_all(shown_at: nil)
        article.persona_comments.where(persona_id: %w[oda-nobunaga joseph-stalin mao-zedong]).update_all(shown_at: 1.minute.ago)
        post article_comments_path(article, except: "oda-nobunaga,joseph-stalin,mao-zedong"), as: :turbo_stream
        expect(shown_names).to include("shuzo-matsuoka")
      end
    end

    it "JS が無いときも、上限で組み替える人がいなければ戻った画面に「今日はもう口を出せません」を出し、ボタンを出さない" do
      post article_comments_path(article)
      first = article.persona_comments.pluck(:persona_id)
      article.persona_comments.update_all(body: "書けた")
      allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true, remaining: 0))

      post article_comments_path(article, except: first.join(","))
      follow_redirect!

      expect(shown_names).to match_array(first)
      expect(page).to have_text("今日はもう口を出せません")
      expect(page).to have_no_button(/別の/)
    end

    it "記録した組の人を全員外すと、残る記録前の行から読み直しと押下で同じ組を出し、表示した組からの押下で次を作る" do
      save(article)
      recorded = %w[oda-nobunaga joseph-stalin mao-zedong]
      article.persona_comments.where(persona_id: recorded).update_all(shown_at: Time.current)
      Persona.where(slug: recorded).update_all(enabled: false)
      article.persona_comments.where(persona_id: "margaret-thatcher").delete_all

      get article_comments_path(article)
      shown = shown_names
      3.times do
        get article_comments_path(article)
        expect(shown_names).to eq(shown)
      end

      post article_comments_path(article, except: shown.join(",")), as: :turbo_stream
      expect(enqueued_slugs).to eq([ "margaret-thatcher" ])
    end

    it "今日の上限に達していたら行も Job も作らずに「今日はもう口を出せません」" do
      allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true, remaining: 0))

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

    it "キューへの登録が例外で失敗した人だけ失敗にして「もう一度」を出し、他の人は積む" do
      calls = 0
      allow(Comments::CommentPersonaJob).to receive(:perform_later).and_wrap_original do |original, *args|
        calls += 1
        calls == 1 ? raise(SolidQueue::Job::EnqueueError, "ActiveRecord::StatementTimeout: database is locked") : original.call(*args)
      end

      post article_comments_path(article), as: :turbo_stream

      expect(article.persona_comments.map(&:state).tally).to eq(failed: 1, writing: 2)
      expect(article.persona_comments.find(&:failed?).error).to eq("Job を積めなかった")
      expect(enqueued_slugs.size).to eq(2)
      expect(response.body).to include("口を出せませんでした", "もう一度")
    end

    it "未生成で今日の上限に達していれば、取り直しても「今日はもう口を出せません」でボタンを出さない" do
      allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true, remaining: 0))

      get article_comments_path(article)

      expect(page).to have_text("今日はもう口を出せません")
      expect(page).to have_no_button("コメントを見る")
    end

    it "書いている途中の人は、その Job が最後の 1 回を使って上限に達しても「書いています」のまま" do
      article.persona_comments.create!(persona_id: "oda-nobunaga")
      allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true, remaining: 0))

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
        post article_comments_path(article, except: before.join(",")), as: :turbo_stream
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
