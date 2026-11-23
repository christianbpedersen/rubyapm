import { Controller } from "@hotwired/stimulus"

// Collapses and expands subtrees of the trace waterfall.
export default class extends Controller {
  toggle(event) {
    const row = event.target.closest(".wf-row")
    const collapsed = row.dataset.collapsed === "1"
    row.dataset.collapsed = collapsed ? "0" : "1"
    event.target.textContent = collapsed ? "▾" : "▸"
    this.setDescendants(row.dataset.id, collapsed)
  }

  setDescendants(id, visible) {
    this.element.querySelectorAll(`.wf-row[data-parent="${id}"]`).forEach((child) => {
      child.hidden = !visible
      // Keep a collapsed child's own subtree hidden when re-expanding.
      if (!visible || child.dataset.collapsed !== "1") this.setDescendants(child.dataset.id, visible)
    })
  }
}
