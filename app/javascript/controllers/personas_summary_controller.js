import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["summary", "list"]
  static values = { shown: Number, messages: Object }

  connect() {
    this.observer = new MutationObserver(() => this.update())
    this.observer.observe(this.listTarget, { childList: true, subtree: true, attributeFilter: ["data-persona-enabled"] })
    this.update()
  }

  disconnect() {
    this.observer.disconnect()
  }

  update() {
    const enabled = this.listTarget.querySelectorAll('[data-persona-enabled="true"]').length
    const { none, all, sampled } = this.messagesValue
    const pattern = enabled === 0 ? none : (enabled <= this.shownValue ? all : sampled)
    const text = pattern.replaceAll("%{enabled}", enabled).replaceAll("%{shown}", this.shownValue)
    if (this.summaryTarget.textContent !== text) this.summaryTarget.textContent = text
  }
}
