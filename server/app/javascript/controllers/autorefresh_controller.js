import { Controller } from "@hotwired/stimulus"

// Re-fetches the current page every `interval` ms. With
// <meta name="turbo-refresh-method" content="morph"> Turbo morphs the new HTML
// into the page (scroll position kept), and charts redraw from their updated
// data attributes. A refresh is skipped while the user is typing, dragging
// across a chart to zoom, or the tab is hidden; coming back to a stale tab
// refreshes right away. Clicking the indicator pauses (remembered per browser).
export default class extends Controller {
  static targets = ["indicator", "label"]
  static values = { interval: { type: Number, default: 10000 } }

  connect() {
    this.paused = this.storedPause()
    this.lastRefresh = Date.now()
    this.pointerDown = false
    this.onPointerDown = () => (this.pointerDown = true)
    this.onPointerUp = () => (this.pointerDown = false)
    this.onVisibility = () => {
      if (!document.hidden && Date.now() - this.lastRefresh >= this.intervalValue) this.refresh()
    }
    this.onLoad = () => {
      this.lastRefresh = Date.now()
      this.render()
    }
    document.addEventListener("pointerdown", this.onPointerDown, true)
    document.addEventListener("pointerup", this.onPointerUp, true)
    document.addEventListener("visibilitychange", this.onVisibility)
    document.addEventListener("turbo:load", this.onLoad)
    document.addEventListener("turbo:morph", this.onLoad)
    this.timer = setInterval(() => this.tick(), 1000)
    this.render()
  }

  disconnect() {
    clearInterval(this.timer)
    document.removeEventListener("pointerdown", this.onPointerDown, true)
    document.removeEventListener("pointerup", this.onPointerUp, true)
    document.removeEventListener("visibilitychange", this.onVisibility)
    document.removeEventListener("turbo:load", this.onLoad)
    document.removeEventListener("turbo:morph", this.onLoad)
  }

  toggle() {
    this.paused = !this.paused
    try { localStorage.setItem("nf-autorefresh-paused", this.paused ? "1" : "0") } catch (e) {}
    if (!this.paused) this.refresh()
    this.render()
  }

  tick() {
    this.render()
    if (this.paused || document.hidden || this.busy()) return
    if (Date.now() - this.lastRefresh >= this.intervalValue) this.refresh()
  }

  // Typing in a field or mid-drag on a chart: try again next second.
  busy() {
    const el = document.activeElement
    const typing = el && (el.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName))
    return typing || this.pointerDown
  }

  refresh() {
    this.lastRefresh = Date.now()
    window.Turbo?.visit(window.location.href, { action: "replace" })
  }

  render() {
    if (!this.hasIndicatorTarget) return
    this.indicatorTarget.classList.toggle("paused", this.paused)
    const secs = Math.max(0, Math.ceil((this.intervalValue - (Date.now() - this.lastRefresh)) / 1000))
    if (this.hasLabelTarget) this.labelTarget.textContent = this.paused ? "Paused" : `Live · ${secs}s`
    this.indicatorTarget.title = this.paused ? "Auto-refresh paused. Click to resume." : "Refreshes every 10 s. Click to pause."
  }

  storedPause() {
    try { return localStorage.getItem("nf-autorefresh-paused") === "1" } catch (e) { return false }
  }
}
