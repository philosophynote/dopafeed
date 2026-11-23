RSpec.describe "Comments", type: :system do
  let(:comments) { { personas_shown: 3, model: "grok-4.3", max_tokens: 4000, timeout_seconds: 60 } }
  let(:bodies) { Persona.enabled.to_h { |persona| [ persona.slug, "#{persona.name}がこの記事にひとこと。" ] } }

  before do
    seed_personas
    allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.merge(comments: comments))
  end

  def shown_ids
    all("[data-persona-id]").map { |card| card["data-persona-id"] }
  end

  it "広げた欄で「コメントを見る」を押すと「考え中」、Job が書き終えると 2 人が現れ、「別の 2 人を見る」で入れ替わる" do
    comments[:personas_shown] = 2
    allow(Comments::Commenter).to receive(:new).and_return(instance_double(Comments::Commenter, call: bodies))
    article = create(:article, :awaiting_summary, summary: "・要約", title: "口を出される記事")
    sign_in

    expand("口を出される記事")
    box = find("section[aria-label='コメント']")
    expect(box).to have_text("? ? ?")
    expect(box).to have_text("人物は AI による架空のキャラクターです。本人の発言ではありません")
    screenshot!("closed")

    box.click_button("コメントを見る")
    expect(page).to have_css("section[aria-label='コメント']", text: "考え中")
    find("##{ActionView::RecordIdentifier.dom_id(article, :comments_box)} turbo-cable-stream-source[connected]", visible: :all)
    screenshot!("pending")

    Comments::CommentArticleJob.perform_now(article)

    expect(page).to have_css("[data-persona-id]", count: 2)
    first = shown_ids
    expect(find("section[aria-label='コメント']")).to have_text("人物は AI による架空のキャラクターです")
    expect(page).to have_current_path(root_path)
    screenshot!("opened")

    click_link "別の 2 人を見る"
    expect(page).to have_no_css(first.map { |id| "[data-persona-id='#{id}']" }.join(", "))
    expect(page).to have_css("[data-persona-id]", count: 2)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
    expect(page).to have_current_path(root_path)
  end

  it "出来上がりの知らせを取りこぼしても、購読がつながり直したときに欄を取り直して 3 人を出す" do
    allow(Comments::Commenter).to receive(:new).and_return(instance_double(Comments::Commenter, call: bodies))
    allow(Comments::CommentArticleJob).to receive(:broadcast)
    article = create(:article, :awaiting_summary, summary: "・要約", title: "知らせを落とす記事")
    sign_in

    expand("知らせを落とす記事")
    click_button "コメントを見る"
    box_id = ActionView::RecordIdentifier.dom_id(article, :comments_box)
    find("##{box_id} turbo-cable-stream-source[connected]", visible: :all)

    # 知らせは止めてあるので、3 人が出るのは購読のつながり直しで欄を取り直したときだけ
    Comments::CommentArticleJob.perform_now(article)
    page.execute_script(<<~JS, box_id)
      const source = document.querySelector(`#${arguments[0]} turbo-cable-stream-source`)
      if (source) { source.removeAttribute("connected"); source.setAttribute("connected", "") }
    JS

    expect(page).to have_css("[data-persona-id]", count: 3)
    expect(page).to have_no_css("##{box_id} turbo-cable-stream-source", visible: :all)
  end

  it "上限の知らせを取りこぼしても、取り直すと上限を出し、購読も外す（畳んだ後に購読が溜まらない）" do
    allow(Comments::Commenter).to receive(:new).and_return(instance_double(Comments::Commenter).tap do |commenter|
      allow(commenter).to receive(:call).and_raise(Claude::Budget::Exhausted, "limit")
    end)
    allow(Comments::CommentArticleJob).to receive(:broadcast)
    article = create(:article, :awaiting_summary, summary: "・要約", title: "上限を落とす記事")
    sign_in

    expand("上限を落とす記事")
    click_button "コメントを見る"
    box_id = ActionView::RecordIdentifier.dom_id(article, :comments_box)
    find("##{box_id} turbo-cable-stream-source[connected]", visible: :all)

    allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true))
    Comments::CommentArticleJob.perform_now(article)
    page.execute_script(<<~JS, box_id)
      const source = document.querySelector(`#${arguments[0]} turbo-cable-stream-source`)
      if (source) { source.removeAttribute("connected"); source.setAttribute("connected", "") }
    JS

    expect(page).to have_css("section[aria-label='コメント']", text: "今日はもう口を出せません")
    expect(page).to have_no_css("##{box_id} turbo-cable-stream-source", visible: :all)
  end

  it "失敗が届くと「口を出せませんでした」、「もう一度」で頼み直して「考え中」に戻る" do
    allow(Comments::Commenter).to receive(:new).and_return(instance_double(Comments::Commenter).tap do |commenter|
      allow(commenter).to receive(:call).and_raise(Comments::Commenter::MalformedResponse, "応答の形式が不正")
    end)
    article = create(:article, :awaiting_summary, summary: "・要約", title: "失敗する記事")
    sign_in

    expand("失敗する記事")
    click_button "コメントを見る"
    find("##{ActionView::RecordIdentifier.dom_id(article, :comments_box)} turbo-cable-stream-source[connected]", visible: :all)
    Comments::CommentArticleJob.perform_now(article)

    expect(page).to have_css("section[aria-label='コメント']", text: "口を出せませんでした")
    screenshot!("failed")
    requested_at = article.reload.comments_requested_at
    click_button "もう一度"

    expect(page).to have_css("section[aria-label='コメント']", text: "考え中")
    expect(article.reload).to have_attributes(comments_failed_at: nil, comments_error: nil)
    expect(article.comments_requested_at).to be > requested_at
  end

  it "今日の上限に達していれば、広げた欄に「今日はもう口を出せません」が出て、押すボタンは出ない" do
    create(:article, :awaiting_summary, summary: "・要約", title: "上限の日の記事")
    allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true))
    sign_in

    expand("上限の日の記事")

    expect(page).to have_css("section[aria-label='コメント']", text: "今日はもう口を出せません")
    expect(page).to have_no_button("コメントを見る")
    screenshot!("exhausted")
  end

  it "yml にコメントの鍵が無ければ、広げた欄にコメントの欄を出さない" do
    comments.delete(:model)
    create(:article, :awaiting_summary, summary: "・要約", title: "鍵の無い日の記事")
    sign_in

    expand("鍵の無い日の記事")

    expect(page).to have_no_css("section[aria-label='コメント']")
  end
end
