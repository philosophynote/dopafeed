# touch エミュレーションは Chrome を固めるため、Pointer Events を JS から送る。
module SystemSwipe
  # 座標はカード左上からの相対値なので、継続操作では移動後のカード位置を基準にする。
  def drag_card(title, from:, to:, steps: 4, release: true, on: nil, down: true)
    card = find("article", text: title)
    page.execute_script(<<~JS, card.native, on&.native, from, to, steps, release, down)
      const [card, origin, from, to, steps, release, down] = arguments
      const rect = card.getBoundingClientRect()
      const fire = (type, x, y) => (origin || card).dispatchEvent(new PointerEvent(type, {
        bubbles: true, cancelable: true, composed: true,
        pointerId: 7, pointerType: "touch", isPrimary: true, button: type === "pointermove" ? -1 : 0, buttons: 1,
        clientX: rect.left + x, clientY: rect.top + y
      }))
      if (down) fire("pointerdown", from[0], from[1])
      for (let i = 1; i <= steps; i++) {
        fire("pointermove", from[0] + (to[0] - from[0]) * i / steps, from[1] + (to[1] - from[1]) * i / steps)
      }
      if (release) fire("pointerup", to[0], to[1])
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

  def swipe_rail(title, target = "rail")
    find("article", text: title).find(:xpath, "..").find("[data-swipe-target='#{target}']", visible: :all)
  end
end

RSpec.configure do |config|
  config.include SystemSwipe, type: :system
end
