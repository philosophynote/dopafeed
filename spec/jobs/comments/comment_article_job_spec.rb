RSpec.describe Comments::CommentArticleJob, type: :job do
  let(:article) { create(:article, :awaiting_summary, :opened) }
  let(:commenter) { instance_double(Comments::Commenter) }
  let(:bodies) { Persona.all.map(&:id).index_with { |id| "#{id} のひとこと" } }

  before { allow(Comments::Commenter).to receive(:new).with(article).and_return(commenter) }

  it "claude キューに積まれる（日次上限を要約と共用する）" do
    expect(described_class.new(article).queue_name).to eq("claude")
  end

  it "8 人分を記事に保存し、前に残した失敗の記録を消す" do
    article.update!(comments_failed_at: Time.current, comments_error: "応答の形式が不正")
    allow(commenter).to receive(:call).and_return(bodies)

    described_class.perform_now(article)

    expect(article.persona_comments.pluck(:persona_id, :body)).to match_array(bodies.to_a)
    expect(article.reload).to have_attributes(comments_failed_at: nil, comments_error: nil)
  end

  it "保存済みなら呼ばない（1 記事 1 回。二度払いしない）" do
    article.persona_comments.create!(persona_id: "oda-nobunaga", body: "既にある")

    described_class.perform_now(article)

    expect(Comments::Commenter).not_to have_received(:new)
  end

  it "呼んでいる間に重なった別の実行が保存していたら、そちらを残して書き足さない" do
    allow(commenter).to receive(:call) do
      Article.find(article.id).persona_comments.create!(persona_id: "oda-nobunaga", body: "先の実行")
      bodies
    end

    described_class.perform_now(article)

    expect(article.persona_comments.pluck(:body)).to eq([ "先の実行" ])
  end

  it "本文なし・形式不正・4xx は失敗として記録し、やり直さない" do
    allow(commenter).to receive(:call).and_raise(Comments::Commenter::MalformedResponse, "応答の形式が不正")

    freeze_time do
      described_class.perform_now(article)
      expect(article.reload).to have_attributes(comments_failed_at: Time.current, comments_error: "応答の形式が不正")
    end
    expect(article.persona_comments).to be_empty
    expect(described_class).not_to have_been_enqueued
  end

  it "失敗の記録も、先に別の実行が保存していれば残さない" do
    allow(commenter).to receive(:call) do
      Article.find(article.id).persona_comments.create!(persona_id: "oda-nobunaga", body: "先の実行")
      raise Comments::Commenter::MalformedResponse, "応答の形式が不正"
    end

    described_class.perform_now(article)

    expect(article.reload).to have_attributes(comments_failed_at: nil, comments_error: nil)
  end

  it "TransientError は待ってやり直し、尽きたら失敗として記録する" do
    allow(commenter).to receive(:call).and_raise(Comments::Commenter::TransientError, "API エラー (HTTP 503)")

    described_class.perform_now(article)
    expect(described_class).to have_been_enqueued.with(article)
    expect(article.reload.comments_failed_at).to be_nil

    perform_enqueued_jobs { described_class.perform_later(article) }
    expect(commenter).to have_received(:call).at_least(3).times
    expect(article.reload).to have_attributes(comments_error: "API エラー (HTTP 503)")
    expect(article.comments_failed_at).to be_present
  end

  it "予算切れは捨て、記事には何も残さない" do
    allow(commenter).to receive(:call).and_raise(Claude::Budget::Exhausted, "Claude daily call limit reached (200/200)")

    expect { described_class.perform_now(article) }.not_to raise_error
    expect(enqueued_jobs).to be_empty
    expect(article.reload).to have_attributes(comments_failed_at: nil, comments_error: nil)
  end

  it "同じ記事の Job は 1 本ずつ走らせ、重なった分は捨てずに待たせる（concurrency key は記事 id）" do
    job = described_class.new(article)
    expect(job).to be_concurrency_limited
    expect(job.concurrency_key).to end_with("/#{article.id}")
    expect(described_class.concurrency_on_conflict).to eq(:block)
  end

  it "記事が消えていたら捨てる" do
    article.destroy!

    expect { perform_enqueued_jobs { described_class.perform_later(article) } }.not_to raise_error
    expect(enqueued_jobs).to be_empty
  end
end
