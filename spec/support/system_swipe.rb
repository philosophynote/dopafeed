# touch エミュレーションは Chrome を固めるため、Pointer Events を JS から送る。
module SystemSwipe
  # 即時の合成イベントでは実行速度次第で払いになるため、閾値手前で戻るテストは slow で時間を確保する。
  SLOW_DRAG_MS = 600

  # 座標は移動後のカード基準なので、継続操作では移動した分を補正する。
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
  # 戻りの transition が終わる前に測ると、途中の移動量を読んでしまう。
  def settled_shift(title)
    Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until card_shift(title).zero? }
    card_shift(title)
  rescue Timeout::Error
    card_shift(title)
  end
  def swipe_rail(title, target = "rail")
    find("article", text: title).find(:xpath, "..").find("[data-swipe-target='#{target}']", visible: :all)
  end
end

RSpec.configure do |config|
  config.include SystemSwipe, type: :system
end
