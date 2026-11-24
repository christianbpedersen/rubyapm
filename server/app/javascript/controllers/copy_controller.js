import { Controller } from "@hotwired/stimulus"

// Copies the source input's value to the clipboard (falls back to selecting it).
export default class extends Controller {
  static targets = ["source", "button"]

  async copy() {
    const text = this.sourceTarget.value
    try {
      await navigator.clipboard.writeText(text)
      this.buttonTarget.textContent = "Copied"
      setTimeout(() => { this.buttonTarget.textContent = "Copy" }, 1500)
    } catch {
      this.sourceTarget.select()
    }
  }
}
