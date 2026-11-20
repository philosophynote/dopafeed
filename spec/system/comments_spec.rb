RSpec.describe "Comments", type: :system do
  let(:comments) { { personas_shown: 3, model: "grok-4.7", max_tokens: 4000, timeout_seconds: 60 } }
  let(:bodies) { Persona.all.to_h { |persona| [ persona.id, "#{persona.name}がこの記事にひとこと。" ] } }

  before { allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.merge(comments: comments)) }

  def shown_ids
    all("[data-persona-id]").map { |card| card["data-persona-id"] }
  end

  it "広げた欄で「コメントを見る」を押すと「考え中」、Job が書き終えると 3 人が現れ、「別の 3 人を見る」で入れ替わる" do
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

    expect(page).to have_css("[data-persona-id]", count: 3)
    first = shown_ids
    expect(find("section[aria-label='コメント']")).to have_text("人物は AI による架空のキャラクターです")
    expect(page).to have_current_path(root_path)
    screenshot!("opened")

    click_link "別の 3 人を見る"
    expect(page).to have_no_css(first.map { |id| "[data-persona-id='#{id}']" }.join(", "))
    expect(page).to have_css("[data-persona-id]", count: 3)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
    expect(page).to have_current_path(root_path)
  end

  it "今日の上限に達していれば、押すと「今日はもう口を出せません」" do
    create(:article, :awaiting_summary, summary: "・要約", title: "上限の日の記事")
    allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true))
    sign_in

    expand("上限の日の記事")
    click_button "コメントを見る"

    expect(page).to have_css("section[aria-label='コメント']", text: "今日はもう口を出せません")
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
