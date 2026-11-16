namespace :judgments do
  # 本数に既定値を置くと、引数を忘れただけで完読の全件ぶん API 料金が掛かる。
  desc "完読した未判定の記事を、完読の新しい順に指定の本数だけ判定する（例: bin/rails 'judgments:backfill[20]'）"
  task :backfill, [ :limit ] => :environment do |_, args|
    # SQLite は LIMIT に負の数を渡すと全件を返す。
    limit = Integer(args[:limit].presence || 0, exception: false)
    abort "本数を 1 以上の整数で指定せよ: bin/rails 'judgments:backfill[20]'" unless limit&.positive?
    abort "config/dopamine.yml の judgment と OPENROUTER_API_KEY が要る" unless Judgments::ArticleScorer.configured?

    articles = Article.awaiting_judgment.joins(:reading).merge(Reading.completed).order("readings.completed_at DESC").limit(limit)
    articles.each do |article|
      JudgeArticleJob.perform_now(article)
      judgment = article.reload.judgment
      line = judgment&.judged? ? "#{judgment.total} 点 #{judgment.points.values.join("/")}" : "失敗 #{judgment&.error || "判定を残せなかった（予算切れ・鍵や残高の失敗・再試行待ち。ログの [judgments] を見よ）"}"
      puts "#{line} #{article.title}"
    end
  end

  desc "判定の本数、合計点ごとの本数、軸ごとの平均、実費の合計を出す"
  task status: :environment do
    judged = ArticleJudgment.judged.to_a
    puts "判定済み #{judged.size} ・ 失敗 #{ArticleJudgment.failed.count} ・ 待ち #{Article.awaiting_judgment.count}"
    judged.group_by(&:total).sort.reverse_each { |total, rows| puts "#{total} 点: #{rows.size} 本" }
    next if judged.empty?

    puts "平均 " + ArticleJudgment::AXES.map { |axis| "#{I18n.t(axis, scope: "judgment.axes", locale: :ja)} #{(judged.sum { |j| j.points[axis] } / judged.size.to_f).round(1)}" }.join(" ・ ")
    puts "実費 $#{judged.sum { |j| j.cost.to_f }.round(4)}（入力 #{judged.sum { |j| j.input_tokens.to_i }} トークン。判定済みのぶんだけで、失敗と再試行のぶんは含まない）"
  end
end
