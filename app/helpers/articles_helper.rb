module ArticlesHelper
  # 要約済みの記事で、予算の台帳を数える問い合わせを打たない。
  def summary_state(article)
    return :ready if article.summary.present?
    return :failed if article.summary_failed_at.present?
    return :exhausted if Claude::Budget.new.exhausted?

    :pending
  end
end
