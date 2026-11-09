import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["close"]
  connect() { this.element.showModal() }
  disconnect() { this.element.close() }
  close(event) { event.preventDefault(); this.closeTarget.click() }
  busy() { this.toggle(true) }
  idle() { this.toggle(false) }
  toggle(disabled) { this.element.querySelectorAll("button, input[type=submit]").forEach(button => { button.disabled = disabled }) }
}
