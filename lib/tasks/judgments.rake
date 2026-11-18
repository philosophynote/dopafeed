namespace :judgments do
  # 本数に既定値を置くと、引数を忘れただけで完読の全件ぶん API 料金が掛かる。
  desc "完読した未判定の記事を、完読の新しい順に指定の本数だけ判定する（例: bin/rails 'judgments:backfill[20]'）"
  task :backfill, [ :limit ] => :environment do |_, args|
    # SQLite は LIMIT に負の数を渡すと全件を返す。
    limit = Integer(args[:limit].presence || 0, exception: false)
    abort "本数を 1 以上の整数で指定せよ: bin/rails 'judgments:backfill[20]'" unless limit&.positive?
    abort "config/dopamine.yml の judgment と TYPESAFE_API_KEY が要る" unless Judgments::ArticleScorer.configured?

    articles = Article.awaiting_judgment.joins(:reading).merge(Reading.completed).order("readings.completed_at DESC").limit(limit)
    articles.each do |article|
      # perform_now は破棄と再試行が例外を飲み、理由を標準出力に出せない。再試行の予約も、キューが async の環境ではプロセスと一緒に消える。
      JudgeArticleJob.new.perform(article)
      judgment = article.reload.judgment
      line = judgment&.judged? ? "#{judgment.total} 点 #{judgment.points.values.join("/")}" : "失敗 #{judgment&.error || "判定を残せなかった（別の実行と重なったか、記事が消えた）"}"
      puts "#{line} #{article.title}"
    rescue Judgments::ArticleScorer::TransientError => e
      puts "失敗 #{e.message}（一時的な失敗。行は残していないので、打ち直せばまた試す） #{article.title}"
    rescue Claude::Budget::Exhausted, Judgments::ArticleScorer::RejectedError => e
      # 続けても同じ理由で落ち、呼ぶたびに日次の台帳だけが減る。
      abort "中止 #{e.message}（4xx は鍵・残高・yml のモデル名・要求の形のどれかで拒まれた。limit は日次の上限。行は残していないので、直してから打ち直せ）"
    end
  end

  # 判定の届いた枠は、境界を変えても自動では動かさない。付け直すのは、打った人が動くカードを見て決めたときだけ。
  desc "判定済みの記事のカードの枠を、今の cards.rarities の境界で付け直す（判定の無い・失敗した記事のカードは動かさない）"
  task regrade: :environment do
    label = ->(tier) { tier ? I18n.t(tier, scope: "dopamine.rarities", locale: :ja) : "判定中" }
    readings = Reading.joins(article: :judgment).merge(ArticleJudgment.judged).includes(article: :judgment).order(:id)
    moved = readings.count do |reading|
      tier = reading.article.judgment.tier
      next false if reading.tier == tier

      puts "#{label.call(reading.tier)} → #{label.call(tier)} #{reading.article.title}"
      reading.update!(tier: tier)
    end
    puts "付け直した #{moved} 枚（判定済み #{readings.size} 枚のうち）"
  end

  desc "判定の本数、合計点ごとの本数、軸ごとの平均、実費の合計を出す"
  task status: :environment do
    judged = ArticleJudgment.judged.to_a
    puts "判定済み #{judged.size} ・ 失敗 #{ArticleJudgment.failed.count} ・ 待ち #{Article.awaiting_judgment.count}"
    judged.group_by(&:total).sort.reverse_each { |total, rows| puts "#{total} 点: #{rows.size} 本" }
    next if judged.empty?

    puts "平均 " + ArticleJudgment::AXES.map { |axis| "#{I18n.t(axis, scope: "judgment.axes", locale: :ja)} #{(judged.sum { |j| j.points[axis] } / judged.size.to_f).round(1)}" }.join(" ・ ")
    # 応答に費用が載らない経路では cost が空のまま残る。0 と足すと「無料」に見える。
    costs = judged.filter_map(&:cost)
    puts "実費 #{costs.empty? ? "不明" : "$#{costs.sum.round(4)}"}（入力 #{judged.sum { |j| j.input_tokens.to_i }} トークン。判定済みのぶんだけで、失敗と再試行のぶんは含まない）"
  end
end
