# 記事の要約欄の出し分け。要約の有無だけでなく、作成中・失敗・その日の上限で文言を変える（{ReadingsHelper} は判定と XP の文言）
module ArticlesHelper
  # 上限を見るのは要約も失敗も無いときだけ（台帳を数える問い合わせを、要約済みの記事で打たない）
  #
  # @return [Symbol] :ready / :failed / :exhausted / :pending
  def summary_state(article)
    return :ready if article.summary.present?
    return :failed if article.summary_failed_at.present?
    return :exhausted if Claude::Budget.new.exhausted?

    :pending
  end
end
