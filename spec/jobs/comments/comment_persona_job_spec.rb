RSpec.describe Comments::CommentPersonaJob, type: :job do
  let(:article) { create(:article, :awaiting_summary, :opened) }
  let(:persona) { Persona.find_by!(slug: "oda-nobunaga") }
  let(:comment) { article.persona_comments.create!(persona_id: persona.slug) }
  let(:commenter) { instance_double(Comments::Commenter) }
  let(:stream) { "#{article.to_gid_param}:comments" }

  before do
    seed_personas
    allow(Comments::Commenter).to receive(:new).with(article, persona).and_return(commenter)
  end

  it "claude キューに積まれる（日次上限を要約と共用する）" do
    expect(described_class.new(comment).queue_name).to eq("claude")
  end

  it "その人の分だけを書いて行に保存し、そのカードを購読している画面へ送る" do
    allow(commenter).to receive(:call).and_return("織田信長のひとこと")

    expect { described_class.perform_now(comment) }
      .to have_broadcasted_to(stream).with(a_string_including("turbo-stream", "replace", ActionView::RecordIdentifier.dom_id(comment), "織田信長のひとこと"))
    expect(comment.reload).to have_attributes(body: "織田信長のひとこと", state: :written)
  end

  it "書いている途中で人物を外しても、頼まれた分は書き上げて残す（戻したときに出せるように）" do
    comment
    persona.update!(enabled: false)
    allow(commenter).to receive(:call).and_return("織田信長のひとこと")

    expect { described_class.perform_now(comment) }
      .to have_broadcasted_to(stream).with(a_string_including("remove", ActionView::RecordIdentifier.dom_id(comment)))
    expect(comment.reload.body).to eq("織田信長のひとこと")
  end

  it "外した人のカードは、本文を送らずに消す知らせだけを送る" do
    comment
    persona.update!(enabled: false)
    allow(commenter).to receive(:call).and_return("織田信長のひとこと")

    expect { described_class.perform_now(comment) }
      .not_to have_broadcasted_to(stream).with(a_string_including("織田信長のひとこと"))
  end

  context "欄に並んだ組（押したときに選んだ人）" do
    let(:other) { article.persona_comments.create!(persona_id: "joseph-stalin") }
    let(:box) { ActionView::RecordIdentifier.dom_id(article, :comments_box) }

    before do
      PersonaComment.where(id: [ comment.id, other.id ]).update_all(shown_at: Time.current)
      allow(commenter).to receive(:call).and_return("織田信長のひとこと")
    end

    it "まだ書いている人がいれば、そのカードだけを送り、欄（購読を含む）は送らない" do
      ActionCable.server.pubsub.clear
      expect { described_class.perform_now(comment) }
        .to have_broadcasted_to(stream).with(a_string_including(%(target="#{ActionView::RecordIdentifier.dom_id(comment)}")))
      expect(ActionCable.server.pubsub.broadcasts(stream).map { |message| ActiveSupport::JSON.decode(message) }).to all(satisfy { |html| !html.include?(box) })
    end

    it "欄を送り直すときは、判定に使った組を描いている欄だけを差し替える（直後に押された新しい組の欄を古い組で上書きしない）" do
      other.update!(body: "スターリンのひとこと")
      lineup = [ comment.id, other.id ].join("-")

      expect { described_class.perform_now(comment) }
        .to have_broadcasted_to(stream).with(a_string_including(%(targets="##{box}[data-lineup=&#39;#{lineup}&#39;]")))
    end

    it "最後の 1 人が書けたら、欄ごと送り直して状態を書き上がりにし、購読を外す" do
      other.update!(body: "スターリンのひとこと")

      expect { described_class.perform_now(comment) }
        .to have_broadcasted_to(stream).with(satisfy { |html|
          html.include?(box) && html.include?("織田信長のひとこと") && html.include?(%(data-state="ready")) && !html.include?("turbo-cable-stream-source")
        })
    end

    it "失敗した人が残っていれば、頼み直しの知らせを受けるため購読は外さない" do
      other.update!(failed_at: Time.current, error: "応答の形式が不正")

      expect { described_class.perform_now(comment) }
        .not_to have_broadcasted_to(stream).with(a_string_including(box))
    end
  end

  it "書き上がっていれば呼ばずにカードだけ送る（記事 × 人物で 1 回。二度払いしない）" do
    comment.update!(body: "既にある")

    expect { described_class.perform_now(comment) }.to have_broadcasted_to(stream).with(a_string_including("既にある"))
    expect(Comments::Commenter).not_to have_received(:new)
  end

  it "本文なし・形式不正・4xx はその人の行に失敗を記録し、やり直さない。失敗のカードを送る" do
    allow(commenter).to receive(:call).and_raise(Comments::Commenter::MalformedResponse, "応答の形式が不正")

    freeze_time do
      expect { described_class.perform_now(comment) }.to have_broadcasted_to(stream).with(a_string_including("口を出せませんでした", "もう一度"))
      expect(comment.reload).to have_attributes(failed_at: Time.current, error: "応答の形式が不正", body: nil)
    end
    expect(described_class).not_to have_been_enqueued
  end

  it "1 人の失敗は他の人の行に触らない" do
    other = article.persona_comments.create!(persona_id: "joseph-stalin")
    allow(commenter).to receive(:call).and_raise(Comments::Commenter::MalformedResponse, "応答の形式が不正")

    described_class.perform_now(comment)

    expect(other.reload.state).to eq(:writing)
  end

  it "TransientError は待ってやり直し、尽きたら失敗として記録する" do
    allow(commenter).to receive(:call).and_raise(Comments::Commenter::TransientError, "API エラー (HTTP 503)")

    described_class.perform_now(comment)
    expect(described_class).to have_been_enqueued.with(comment)
    expect(comment.reload.state).to eq(:writing)

    perform_enqueued_jobs { described_class.perform_later(comment) }
    expect(commenter).to have_received(:call).at_least(3).times
    expect(comment.reload).to have_attributes(state: :failed, error: "API エラー (HTTP 503)")
  end

  it "想定外の例外（鍵の欠け・DB の混雑など）も失敗として記録してから上げ直し、書いている途中のまま残さない" do
    allow(commenter).to receive(:call).and_raise(KeyError, "key not found: \"XAI_API_KEY\"")

    expect { described_class.perform_now(comment) }.to raise_error(KeyError)
    expect(comment.reload).to have_attributes(state: :failed, error: "予期しない失敗 (KeyError)")
  end

  it "予算切れは捨て、その人の行は上限の表示にして送る（翌日に頼み直せるよう行は残す）" do
    allow(commenter).to receive(:call).and_raise(Claude::Budget::Exhausted, "Claude daily call limit reached (200/200)")
    allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true))

    expect { described_class.perform_now(comment) }.to have_broadcasted_to(stream).with(a_string_including("今日はもう口を出せません"))
    expect(enqueued_jobs).to be_empty
    expect(comment.reload.state).to eq(:failed)
  end

  it "失敗の記録も、先に別の実行が書き上げていれば残さない" do
    allow(commenter).to receive(:call) do
      PersonaComment.find(comment.id).update!(body: "先の実行")
      raise Comments::Commenter::MalformedResponse, "応答の形式が不正"
    end

    described_class.perform_now(comment)

    expect(comment.reload).to have_attributes(body: "先の実行", failed_at: nil)
  end

  it "同じ行の Job は 1 本ずつ走らせ、重なった分は捨てずに待たせる（concurrency key は行の id）" do
    job = described_class.new(comment)
    expect(job).to be_concurrency_limited
    expect(job.concurrency_key).to end_with("/#{comment.id}")
    expect(described_class.concurrency_on_conflict).to eq(:block)
  end

  it "行が消えていたら（記事ごと消えたなど）捨てる" do
    comment
    article.destroy!

    expect { perform_enqueued_jobs { described_class.perform_later(comment) } }.not_to raise_error
    expect(enqueued_jobs).to be_empty
  end
end
