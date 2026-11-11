RSpec.describe "Bookmarks from Saved", type: :request do
  include ActionView::RecordIdentifier

  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }

  def page
    Capybara.string(response.body.gsub(%r{</?template>}, ""))
  end

  before { sign_in_as(create(:user)) }

  it "保存を外すと行を隠して画面下に「元に戻す」のトーストを出し、保存数と Main の未読数を合わせる" do
    article = create(:article, :bookmarked, title: "外す記事")
    create(:article, :bookmarked)

    delete article_bookmark_path(article, from: "saved"), headers: turbo

    expect(article.reload).not_to be_bookmarked
    row = page.find("turbo-stream[action='replace'][target='#{dom_id(article)}']", visible: :all)
    expect(row).to have_css("li##{dom_id(article)}[hidden]", visible: :all)
    toast = page.find("turbo-stream[action='update'][target='toast']")
    expect(toast).to have_css("[data-controller='toast']", text: "1 件の保存を外しました")
    expect(toast.find("form[action='#{article_bookmark_path(article, from: "saved")}']")).to have_button("元に戻す")
    expect(page.find("turbo-stream[action='update'][target='saved-count']")).to have_text("1")
    expect(page.find("turbo-stream[action='replace'][target='unread-badge']")).to have_css("[data-unread-badge]", text: "1")
  end

  it "スワイプが付けた送信の番号（swipe）をトーストに渡す" do
    article = create(:article, :bookmarked)

    delete article_bookmark_path(article, from: "saved"), params: { swipe: 5 }, headers: turbo

    expect(page).to have_css("turbo-stream[target='toast'] [data-controller='toast'][data-toast-swipe-value='5']", visible: :all)
  end

  it "「元に戻す」で保存し直し、隠した行を Saved の行に戻してトーストを消し、保存数を合わせる" do
    article = create(:article, title: "戻す記事")

    post article_bookmark_path(article, from: "saved"), headers: turbo

    expect(article.reload).to be_bookmarked
    row = page.find("turbo-stream[action='replace'][target='#{dom_id(article)}']")
    expect(row).to have_css("article h2", text: "戻す記事")
    expect(row).to have_css("form[hidden][action='#{article_bookmark_path(article, from: "saved")}']", visible: :all)
    expect(page.find("turbo-stream[action='update'][target='toast']", visible: :all).text(:all)).to be_blank
    expect(page.find("turbo-stream[action='update'][target='saved-count']")).to have_text("1")
    expect(page.find("turbo-stream[action='replace'][target='unread-badge']")).to have_no_css("[data-unread-badge]")
  end

  it "JS が無ければ Saved へ戻る" do
    article = create(:article, :bookmarked)

    delete article_bookmark_path(article, from: "saved")
    expect(response).to redirect_to(saved_path)

    post article_bookmark_path(article, from: "saved")
    expect(response).to redirect_to(saved_path)
  end
end
