# ENV を一時的に差し替える。ブロックを抜けたら元に戻す。
module EnvHelper
  # @param values [Hash{String => String, nil}] 差し替える値。nil はその鍵を消す
  # @yield 差し替えた状態で実行する処理
  # @return [Object] ブロックの戻り値
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
end
