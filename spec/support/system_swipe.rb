# 一覧の行を引くシステムテストの手。system spec は touch を切っている（spec/support/system_click.rb）ので、Pointer Events を JS から送って作る。
# 本物の指との違いは座標の出どころだけで、横か縦かの判定・閾値・form の送信は同じ道を通る
module SystemSwipe
  # カードの上で pointer を押し、動かし、離す。x / y はカードの左上からの CSS px、steps は途中の pointermove の数。
  # on を渡すと、その要素の上で始めた触りになる（イベントはカードまで bubbling する）。
  # down: false は離さずに止めた指をそのまま動かし続ける（pointerdown を送らない）。座標は動いた後のカードの左上から。
  # release: :cancel は離す代わりに pointercancel（iOS が途中で指を取り上げた）で終える。
  # 既定は一瞬で動かす（時刻の差がほぼ無く、払いとしては測れない）。ms を渡すとその長さをかけて動かす（払う手）。
  # slow: true は SLOW_DRAG_MS かけて動かす。タイマーは早くは来ないので、払う速さは距離 ÷ SLOW_DRAG_MS より遅いと言い切れる。
  # 閾値の手前で離して戻ることを見る手は slow にする（yml に払いの鍵が足されても戻る）
  SLOW_DRAG_MS = 600

  def drag_card(title, from:, to:, steps: 4, release: true, on: nil, down: true, slow: false, ms: nil)
    duration = slow ? SLOW_DRAG_MS : ms.to_i
    raise ArgumentError, "時間をかけて動かすには steps が 1 以上要る" if duration.positive? && steps < 1

    card = find("article", text: title)
    ending = { true => "pointerup", cancel: "pointercancel" }[release]
    page.evaluate_async_script(<<~JS, card.native, on&.native, from, to, steps, ending, down, duration)
      const [card, origin, from, to, steps, ending, down, duration, done] = arguments
      const rect = card.getBoundingClientRect()
      const fire = (type, x, y) => (origin || card).dispatchEvent(new PointerEvent(type, {
        bubbles: true, cancelable: true, composed: true,
        pointerId: 7, pointerType: "touch", isPrimary: true, button: type === "pointermove" ? -1 : 0, buttons: 1,
        clientX: rect.left + x, clientY: rect.top + y
      }))
      const moveTo = (i) => fire("pointermove", from[0] + (to[0] - from[0]) * i / steps, from[1] + (to[1] - from[1]) * i / steps)
      const finish = () => {
        if (ending) fire(ending, to[0], to[1])
        done()
      }
      if (down) fire("pointerdown", from[0], from[1])
      if (!duration) {
        for (let i = 1; i <= steps; i++) moveTo(i)
        return finish()
      }
      let i = 0
      const step = () => {
        moveTo(++i)
        i < steps ? setTimeout(step, duration / steps) : finish()
      }
      setTimeout(step, duration / steps)
    JS
  end

  def card_width(title)
    find("article", text: title).evaluate_script("this.getBoundingClientRect().width")
  end

  def card_shift(title)
    find("article", text: title).evaluate_script("new DOMMatrixReadOnly(getComputedStyle(this).transform).m41")
  end

  def rail_opacity(title)
    find("article", text: title).evaluate_script("parseFloat(getComputedStyle(this.parentElement.querySelector('[data-swipe-target=rail]')).opacity)")
  end

  # 離した後の戻りは transition（200ms）で動くので、止まるまで待ってから位置を見る
  def settled_shift(title)
    Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until card_shift(title).zero? }
    card_shift(title)
  rescue Timeout::Error
    card_shift(title)
  end

  # 行の中の背景（rail）。target は削除・保存を外すなら "rail"、保存なら "saveRail"
  def swipe_rail(title, target = "rail")
    find("article", text: title).find(:xpath, "..").find("[data-swipe-target='#{target}']", visible: :all)
  end
end

RSpec.configure do |config|
  config.include SystemSwipe, type: :system
end
