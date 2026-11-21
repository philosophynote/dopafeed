module EnvHelper
  def with_env(values)
    saved = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end

RSpec.configure do |config|
  config.include EnvHelper

  # 手元のシェルに本物の鍵があると、鍵の有無で分かれる振る舞いが CI と食い違う。
  # 鍵が要る例は、自分の around で with_env して入れる（全体の around の内側で動く）。
  config.around do |example|
    with_env(%w[ANTHROPIC_API_KEY TYPESAFE_API_KEY VAPID_PUBLIC_KEY VAPID_PRIVATE_KEY VAPID_SUBJECT].index_with(nil)) { example.run }
  end
end
