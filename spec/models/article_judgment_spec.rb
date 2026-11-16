RSpec.describe ArticleJudgment do
  it "0 始まりの小数の段を、四捨五入して 1〜5 の点に直す" do
    judgment = build(:article_judgment, originality: 3.5, depth: 3.49, practicality: 0.0, evidence: 4.0, insight: 2.5, applicability: 0.4)

    expect(judgment.points).to eq("originality" => 5, "depth" => 4, "practicality" => 1, "evidence" => 5, "insight" => 4, "applicability" => 1)
  end

  it "合計は見せる 6 つの点の和（小数の和を丸めない。レーダーの数を足すと合計になる）" do
    judgment = build(:article_judgment, originality: 2.5, depth: 2.5, practicality: 2.5, evidence: 2.5, insight: 2.5, applicability: 2.5)

    expect(judgment.total).to eq(24)
  end

  it "失敗の行には点も合計も無い" do
    judgment = build(:article_judgment, :failed)

    expect(judgment).not_to be_judged
    expect(judgment.points).to be_nil
    expect(judgment.total).to be_nil
  end

  it "段の範囲（0〜4）を外れた値は保存しない" do
    expect(build(:article_judgment, depth: 4.2)).not_to be_valid
    expect(build(:article_judgment, depth: -0.1)).not_to be_valid
  end

  it "記事 1 本に 1 行だけ（DB の一意制約）" do
    article = create(:article)
    create(:article_judgment, article: article)

    expect { create(:article_judgment, article: article) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "記事を消すと判定も消える" do
    judgment = create(:article_judgment)

    expect { judgment.article.destroy! }.to change(described_class, :count).by(-1)
  end

  describe "Article.awaiting_judgment" do
    it "読むと決めた・本文取得を試し終えた・まだ判定の行が無い記事だけ" do
      target = create(:article, :awaiting_summary, :opened)
      create(:article, :awaiting_summary)
      create(:article, :opened, content_fetched_at: nil)
      create(:article_judgment, article: create(:article, :awaiting_summary, :opened))
      create(:article_judgment, :failed, article: create(:article, :awaiting_summary, :opened))

      expect(Article.awaiting_judgment).to contain_exactly(target)
    end
  end
end
