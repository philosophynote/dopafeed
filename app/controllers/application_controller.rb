class ApplicationController < ActionController::Base
  include Authentication
  allow_browser versions: :modern

  stale_when_importmap_changes

  helper_method :unread_count

  private

  # @unread_count を共用すると、一覧の絞り込みでアイコンのバッジまで絞った数になる。
  def unread_count
    @app_unread_count ||= Article.unread.count
  end
end
