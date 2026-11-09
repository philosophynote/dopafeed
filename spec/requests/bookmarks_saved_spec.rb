RSpec.describe "Bookmarks from Saved", type: :request do
  include ActionView::RecordIdentifier

  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }

  def page
    Capybara.string(response.body.gsub(%r{</?template>}, ""))
  end

  before { sign_in_as(create(:user)) }

  it "保存を外すと行を「保存を外した ・ 元に戻す」の帯に替え、保存数と Main の未読数を合わせる" do
    article = create(:article, :bookmarked, title: "外す記事")
    create(:article, :bookmarked)

    delete article_bookmark_path(article, from: "saved"), headers: turbo

    expect(article.reload).not_to be_bookmarked
    band = page.find("turbo-stream[action='replace'][target='#{dom_id(article)}']")
    expect(band).to have_text("「外す記事」の保存を外した")
    expect(band.find("form[action='#{article_bookmark_path(article, from: "saved")}']")).to have_button("元に戻す")
    expect(page.find("turbo-stream[action='update'][target='saved-count']")).to have_text("1")
    expect(page.find("turbo-stream[action='replace'][target='unread-badge']")).to have_css("[data-unread-badge]", text: "1")
  end

  it "「元に戻す」で保存し直し、帯を Saved の行に戻して保存数を合わせる" do
    article = create(:article, title: "戻す記事")

    post article_bookmark_path(article, from: "saved"), headers: turbo

    expect(article.reload).to be_bookmarked
    row = page.find("turbo-stream[action='replace'][target='#{dom_id(article)}']")
    expect(row).to have_css("article h2", text: "戻す記事")
    expect(row).to have_css("form[hidden][action='#{article_bookmark_path(article, from: "saved")}']", visible: :all)
    expect(row).to have_no_text("を保存した")
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
