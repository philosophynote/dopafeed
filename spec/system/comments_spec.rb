RSpec.describe "Comments", type: :system do
  let(:comments) { { personas_shown: 3, model: "grok-4.3", max_tokens: 4000, timeout_seconds: 60 } }

  before do
    seed_personas
    allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.merge(comments: comments))
    allow(Comments::Commenter).to receive(:new) do |_article, persona|
      instance_double(Comments::Commenter, call: "#{persona.name}がこの記事にひとこと。")
    end
  end

  def shown_ids
    all("[data-persona-id]").map { |card| card["data-persona-id"] }
  end

  # つながった直後の取り直しが、後から書いた知らせより遅れて届くと古い欄に戻るので、取り直しが終わるまで待つ
  def wait_for_subscription(article)
    find("##{ActionView::RecordIdentifier.dom_id(article, :comments_box)} turbo-cable-stream-source[connected]", visible: :all)
    find("turbo-frame##{ActionView::RecordIdentifier.dom_id(article, :comments)}[complete]", visible: :all)
  end

  def write(comment)
    Comments::CommentPersonaJob.perform_now(comment)
  end

  it "「コメントを見る」で 2 人の枠が「書いています」で出て、書けた人から本文に変わる。「別の 2 人を見る」はまだ作っていない人を作る" do
    comments[:personas_shown] = 2
    article = create(:article, :awaiting_summary, summary: "・要約", title: "口を出される記事")
    sign_in

    expand("口を出される記事")
    box = find("section[aria-label='コメント']")
    expect(box).to have_text("? ? ?")
    expect(box).to have_text("人物は AI による架空のキャラクターです。本人の発言ではありません")
    screenshot!("closed")

    box.click_button("コメントを見る")
    expect(page).to have_css("li[data-state='writing']", count: 2, text: "書いています")
    wait_for_subscription(article)
    screenshot!("writing")

    first, second = article.persona_comments.order(:id).to_a
    write(first)
    expect(page).to have_css("[data-persona-id='#{first.persona_id}']", text: "#{first.persona.name}がこの記事にひとこと。")
    expect(page).to have_css("[data-persona-id='#{second.persona_id}'][data-state='writing']")
    screenshot!("partly-written")

    write(second)
    expect(page).to have_css("li[data-state='written']", count: 2)
    expect(page).to have_css("section[aria-label='コメント'][data-state='ready']")
    expect(page).to have_no_css("turbo-cable-stream-source", visible: :all)
    expect(page).to have_current_path(root_path)
    screenshot!("opened")

    before = shown_ids
    click_button "別の 2 人を見る"
    expect(page).to have_no_css(before.map { |id| "[data-persona-id='#{id}']" }.join(", "))
    expect(page).to have_css("li[data-state='writing']", count: 2)
    expect(article.persona_comments.count).to eq(4)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
    expect(page).to have_current_path(root_path)
  end

  it "出来上がりの知らせを取りこぼしても、購読がつながり直したときに欄を取り直して本文を出し、購読を外す" do
    allow(Comments::CommentPersonaJob).to receive(:broadcast)
    article = create(:article, :awaiting_summary, summary: "・要約", title: "知らせを落とす記事")
    sign_in

    expand("知らせを落とす記事")
    click_button "コメントを見る"
    box_id = ActionView::RecordIdentifier.dom_id(article, :comments_box)
    wait_for_subscription(article)

    # 知らせは止めてあるので、本文が出るのは購読のつながり直しで欄を取り直したときだけ
    article.persona_comments.each { |comment| write(comment) }
    page.execute_script(<<~JS, box_id)
      const source = document.querySelector(`#${arguments[0]} turbo-cable-stream-source`)
      if (source) { source.removeAttribute("connected"); source.setAttribute("connected", "") }
    JS

    expect(page).to have_css("li[data-state='written']", count: 3)
    expect(page).to have_no_css("##{box_id} turbo-cable-stream-source", visible: :all)
  end

  it "1 人だけ失敗すると、その人のカードに「口を出せませんでした」と「もう一度」。押すとその人だけ「書いています」に戻る" do
    article = create(:article, :awaiting_summary, summary: "・要約", title: "失敗する記事")
    sign_in

    expand("失敗する記事")
    click_button "コメントを見る"
    wait_for_subscription(article)
    failing, *others = article.persona_comments.order(:id).to_a
    allow(Comments::Commenter).to receive(:new).with(article, failing.persona)
      .and_return(instance_double(Comments::Commenter).tap { |c| allow(c).to receive(:call).and_raise(Comments::Commenter::MalformedResponse, "応答の形式が不正") })
    [ failing, *others ].each { |comment| write(comment) }

    card = find("[data-persona-id='#{failing.persona_id}']")
    expect(card).to have_text("口を出せませんでした")
    expect(page).to have_css("li[data-state='written']", count: 2)
    screenshot!("failed")

    card.click_button("もう一度")

    expect(page).to have_css("[data-persona-id='#{failing.persona_id}'][data-state='writing']", text: "書いています")
    expect(failing.reload.state).to eq(:writing)
    expect(page).to have_css("li[data-state='written']", count: 2)
  end

  it "購読が切れている間に「もう一度」を押しても、つながり直したときに欄を取り直して「書いています」を出す" do
    article = create(:article, :awaiting_summary, summary: "・要約", title: "切れ間に頼み直す記事")
    comment = article.persona_comments.create!(persona_id: "oda-nobunaga", failed_at: Time.current, error: "応答の形式が不正", shown_at: Time.current)
    sign_in

    expand("切れ間に頼み直す記事")
    wait_for_subscription(article)
    allow(Comments::CommentPersonaJob).to receive(:broadcast)
    click_button "もう一度"
    page.document.synchronize { raise Capybara::ExpectationNotMet, "頼み直しが届いていない" unless comment.reload.writing? }
    expect(page).to have_text("口を出せませんでした")

    page.execute_script(<<~JS, ActionView::RecordIdentifier.dom_id(article, :comments_box))
      const source = document.querySelector(`#${arguments[0]} turbo-cable-stream-source`)
      source.removeAttribute("connected"); source.setAttribute("connected", "")
    JS

    expect(page).to have_css("[data-persona-id='oda-nobunaga'][data-state='writing']", text: "書いています")
  end

  it "今日の上限に達した後の「別の 2 人を見る」は、組み替える人がいなければ同じ組のままボタンの位置に「今日はもう口を出せません」" do
    comments[:personas_shown] = 2
    article = create(:article, :awaiting_summary, summary: "・要約", title: "上限で次が無い記事")
    sign_in

    expand("上限で次が無い記事")
    click_button "コメントを見る"
    wait_for_subscription(article)
    article.persona_comments.each { |comment| write(comment) }
    expect(page).to have_css("li[data-state='written']", count: 2)
    before = shown_ids
    allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true, remaining: 0))

    click_button "別の 2 人を見る"

    expect(page).to have_css("section[aria-label='コメント']", text: "今日はもう口を出せません")
    expect(page).to have_no_button("別の 2 人を見る")
    expect(shown_ids).to match_array(before)
    screenshot!("exhausted-next")
  end

  it "書いている途中で今日の上限に達した人のカードは「今日はもう口を出せません」になる" do
    article = create(:article, :awaiting_summary, summary: "・要約", title: "途中で上限の記事")
    sign_in

    expand("途中で上限の記事")
    click_button "コメントを見る"
    wait_for_subscription(article)
    comment = article.persona_comments.first
    allow(Comments::Commenter).to receive(:new).with(article, comment.persona)
      .and_return(instance_double(Comments::Commenter).tap { |c| allow(c).to receive(:call).and_raise(Claude::Budget::Exhausted, "limit") })
    allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true, remaining: 0))
    write(comment)

    expect(page).to have_css("[data-persona-id='#{comment.persona_id}']", text: "今日はもう口を出せません")
    expect(page).to have_no_button("もう一度")
  end

  it "今日の上限に達していれば、広げた欄に「今日はもう口を出せません」が出て、押すボタンは出ない" do
    create(:article, :awaiting_summary, summary: "・要約", title: "上限の日の記事")
    allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true, remaining: 0))
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
