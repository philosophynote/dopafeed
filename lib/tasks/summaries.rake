# 要約の運用。本番は console を開かずに `kamal app exec --reuse "bin/rails summaries:status"` で打てるようにする（docs/runbook.md）
namespace :summaries do
  desc "要約に失敗した記事を要約待ちに戻す（API は呼ばない。定期の要約ジョブがその日の予算の範囲で拾う）"
  task retry: :environment do
    count = Article.retry_failed_summaries
    remaining = Claude::Budget.new.remaining
    if count.zero?
      puts "要約に失敗した記事はありません。今日の予算の残りは #{remaining} 回です"
    else
      puts "#{count} 本を要約待ちに戻しました。次の定期の要約ジョブが、今日の予算の残り（#{remaining} 回）の範囲で拾います"
    end
  end

  desc "要約の状況（要約済み・待ち・本文取得前・失敗の数、失敗の内訳、今日の予算）"
  task status: :environment do
    unsummarized = Article.where(summary: nil, summary_failed_at: nil)
    puts "要約済み #{Article.where.not(summary: nil).count} / 要約待ち #{Article.awaiting_summary.count} / " \
         "本文取得前 #{unsummarized.where(content_fetched_at: nil).count} / 失敗 #{Article.summary_failed.count}"

    errors = Article.summary_failed.group(:summary_error).count.sort_by { |message, count| [ -count, message.to_s ] }
    if errors.any?
      puts "失敗の内訳:"
      errors.each { |message, count| puts "  #{count} #{message}" }
    end

    budget = Claude::Budget.new
    puts "今日の予算: #{budget.used_today} / #{budget.limit} 回"
  end
end
