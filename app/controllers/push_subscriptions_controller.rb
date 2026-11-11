class PushSubscriptionsController < ApplicationController
  def create
    # 鍵の無いサーバーで購読を預かっても送れないので、保存せずに止める
    return head :service_unavailable unless Push::Vapid.configured?

    # 壊れた keys（文字列など）で 500 にせず、鍵の欠けとして扱う。
    keys = params[:keys].is_a?(ActionController::Parameters) ? params[:keys] : {}
    subscription = PushSubscription.register(
      endpoint: params[:endpoint], p256dh: keys[:p256dh], auth: keys[:auth], user_agent: request.user_agent
    )
    if subscription.errors.any?
      head :unprocessable_entity
    else
      head subscription.previously_new_record? ? :created : :ok
    end
  end

  def destroy
    PushSubscription.where(endpoint: params[:endpoint]).destroy_all
    head :no_content
  end

  private

  # fetch からの呼び出しにログイン画面へのリダイレクトを返しても端末は読めないので、401 で止める
  def request_authentication
    head :unauthorized
  end
end
