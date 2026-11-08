require "rake"

RSpec.describe "articles:refetch_images" do
  include ActiveJob::TestHelper

  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == "articles:refetch_images" } }

  let(:task) { Rake::Task["articles:refetch_images"] }

  after { task.reenable }

  it "画像の無い未読だけ、本文取得の印を外して取得 Job を積み直す" do
    fetched_at = Time.zone.local(2026, 10, 1, 10)
    target = create(:article, content_fetched_at: fetched_at)
    with_image = create(:article, content_fetched_at: fetched_at, image_url: "https://cdn.example.com/og.png")
    read = create(:article, :read, content_fetched_at: fetched_at)
    dismissed = create(:article, :dismissed, content_fetched_at: fetched_at)
    pending = create(:article, content_fetched_at: nil)

    expect { task.invoke }.to output(/1 本/).to_stdout
                                .and have_enqueued_job(FetchArticleContentJob).with(target).exactly(:once)

    expect(target.reload.content_fetched_at).to be_nil
    [ with_image, read, dismissed ].each { |article| expect(article.reload.content_fetched_at).to eq(fetched_at) }
    expect(FetchArticleContentJob).not_to have_been_enqueued.with(with_image)
    expect(FetchArticleContentJob).not_to have_been_enqueued.with(pending)
  end

  it "Job を積めなかったら本文取得の印を戻して止まる（印を外したまま取り残さない）" do
    fetched_at = Time.zone.local(2026, 10, 1, 10)
    article = create(:article, content_fetched_at: fetched_at)
    allow(FetchArticleContentJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue down")

    expect { task.invoke }.to raise_error(ActiveJob::EnqueueError)
    expect(article.reload.content_fetched_at).to eq(fetched_at)
  end
end
