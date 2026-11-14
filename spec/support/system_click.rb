# click は chromedriver に合成させず、要素の click() で送る。
# chromedriver が合成する mouse click（Input.dispatchMouseEvent）は、Turbo が body を差し替えた直後などに
# 文書へ届かないことがある。touch で送る手は取れない（spec/support/system.rb の add_emulation）。
# 見えていることは Capybara の find が確かめる。覆われていないことは chromedriver の Element Click が確かめていたので、
# 画面の中央へ寄せてから自分で見て、覆われていれば chromedriver に任せる（従来どおり ElementClickInterceptedError になる）。
# 失うもの: focus が移らない、:hover と :active が付かない、遷移の完了を待たない（直後の have_current_path などで待つ）。
# option は click() では選べないので select はそのまま chromedriver に任せる。修飾キー・座標・delay 付きの click も同じ
module SystemJsClick
  def click(keys = [], **options)
    plain = keys.empty? && !(options[:x] && options[:y]) && (options[:delay] || 0).zero?
    return super unless plain && tag_name != "option"

    scroll_to_center
    return super if obscured?

    driver.execute_script("arguments[0].click()", native)
  end
end
Capybara::Selenium::Node.prepend(SystemJsClick)

# 要素の click() は呼んだスクリプトが終わるまでマイクロタスクを回さないので、指で押したときと submit 中の動きが変わる。
# 指で押す道を確かめる例だけ、chromedriver が合成するブラウザの click（中央を押す）で送る
module SystemNativeClick
  def native_click(node)
    node.click(x: 0, y: 0)
  end
end
RSpec.configure { |config| config.include SystemNativeClick, type: :system }
