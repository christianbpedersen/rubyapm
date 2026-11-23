import { Controller } from "@hotwired/stimulus"

// Light/dark toggle. The choice is saved per browser; until the user picks
// one, the page follows the operating system. Charts are told to redraw.
export default class extends Controller {
  toggle() {
    const root = document.documentElement
    const dark = root.dataset.theme ? root.dataset.theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches
    const next = dark ? "light" : "dark"
    root.dataset.theme = next
    try { localStorage.setItem("nf-theme", next) } catch (e) {}
    window.dispatchEvent(new CustomEvent("nf:themechange"))
  }
}
