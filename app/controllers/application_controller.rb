class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :unread_count

  private

  # 未読の数。アイコンのバッジがどのページでも使うので、ここで 1 リクエスト 1 回だけ数える。
  # 変数名を @unread_count にしないのは、一覧を絞ったときにバッジまで絞った数にならないよう、各アクションの @unread_count と切り離すため
  def unread_count
    @app_unread_count ||= Article.unread.count
  end
end
