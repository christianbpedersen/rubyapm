import { Controller } from "@hotwired/stimulus"

// Click a column header to sort the table by it; click again to reverse.
// Values come from data-sort-value when a cell has one (timestamps), else are
// parsed from the text: durations ("83 ms", "1.6 s"), rates ("1,944 rpm"),
// percentages, counts ("5,210", "12×"), byte sizes, otherwise plain text.
// Empty values ("–") always sort last. Headers that already link to a
// server-side sort keep their link. The chosen sort is remembered for the
// session and re-applied after the 10-second auto-refresh morphs the page.
export default class extends Controller {
  connect() {
    this.onClick = (event) => {
      const th = event.target.closest("th")
      if (!th || !this.element.contains(th) || th.querySelector("a")) return
      const index = this.headers().indexOf(th)
      if (index < 0 || !th.classList.contains("sortable")) return
      const current = this.state()
      const numeric = this.isNumericColumn(index)
      let dir = numeric ? "desc" : "asc"
      if (current && current.col === index) dir = current.dir === "asc" ? "desc" : "asc"
      this.save({ col: index, dir })
      this.apply()
    }
    this.onKey = (event) => {
      if ((event.key === "Enter" || event.key === " ") && event.target.matches("th.sortable")) {
        event.preventDefault()
        event.target.click()
      }
    }
    this.onMorph = () => this.apply()
    this.element.addEventListener("click", this.onClick)
    this.element.addEventListener("keydown", this.onKey)
    document.addEventListener("turbo:morph", this.onMorph)
    this.apply()
  }

  disconnect() {
    this.element.removeEventListener("click", this.onClick)
    this.element.removeEventListener("keydown", this.onKey)
    document.removeEventListener("turbo:morph", this.onMorph)
  }

  headers() {
    const row = this.element.tHead?.rows[0]
    return row ? [...row.cells] : []
  }

  rows() {
    const body = this.element.tBodies[0]
    return body ? [...body.rows].filter((r) => !r.querySelector("td.empty")) : []
  }

  // Mark sortable headers (morphs strip client-added classes) and sort.
  apply() {
    const rows = this.rows()
    const state = this.state()
    this.headers().forEach((th, i) => {
      const linked = !!th.querySelector("a")
      const sortable = !linked && rows.length > 1 && rows.some((r) => this.value(r, i) !== null)
      th.classList.toggle("sortable", sortable)
      if (sortable) { th.tabIndex = 0 } else { th.removeAttribute("tabindex") }
      th.removeAttribute("aria-sort")
      th.classList.remove("sorted-asc", "sorted-desc")
    })
    if (!state || rows.length < 2) return
    const th = this.headers()[state.col]
    if (!th || !th.classList.contains("sortable")) return

    th.classList.add(state.dir === "asc" ? "sorted-asc" : "sorted-desc")
    th.setAttribute("aria-sort", state.dir === "asc" ? "ascending" : "descending")
    const sign = state.dir === "asc" ? 1 : -1
    const keyed = rows.map((row, position) => ({ row, position, value: this.value(row, state.col) }))
    keyed.sort((a, b) => {
      if (a.value === null && b.value === null) return a.position - b.position
      if (a.value === null) return 1
      if (b.value === null) return -1
      const cmp = typeof a.value === "number" && typeof b.value === "number"
        ? a.value - b.value
        : String(a.value).localeCompare(String(b.value), undefined, { numeric: true, sensitivity: "base" })
      return cmp === 0 ? a.position - b.position : sign * cmp
    })
    const body = this.element.tBodies[0]
    keyed.forEach(({ row }) => body.appendChild(row))
  }

  isNumericColumn(index) {
    return this.rows().some((r) => typeof this.value(r, index) === "number")
  }

  value(row, index) {
    const cell = row.cells[index]
    if (!cell) return null
    if (cell.dataset.sortValue !== undefined) {
      const n = parseFloat(cell.dataset.sortValue)
      return Number.isNaN(n) ? cell.dataset.sortValue : n
    }
    // Share bars and badges carry their number in a label.
    const label = cell.querySelector(".share-label")
    return parseCell((label || cell).textContent)
  }

  // Per page path and header row, for this browser session.
  key() {
    const headers = this.headers().map((th) => th.textContent.trim()).join("|")
    return `nf-sort:${window.location.pathname}:${headers}`
  }

  state() {
    try { return JSON.parse(sessionStorage.getItem(this.key())) } catch (e) { return null }
  }

  save(state) {
    try { sessionStorage.setItem(this.key(), JSON.stringify(state)) } catch (e) {}
  }
}

const UNITS = { ms: 1, s: 1000, rpm: 1, "%": 1, pp: 1, b: 1, kb: 1024, mb: 1024 ** 2, gb: 1024 ** 3, "×": 1 }

function parseCell(raw) {
  const text = raw.replace(/\s+/g, " ").trim()
  if (text === "" || text === "–" || text === "-") return null
  // Leading number with an optional sign and unit: "1,944 rpm", "−32 s/min", "83 ms", "12×", "0.46%".
  const m = text.match(/^([+\-−±]?)\s*([\d.,]+)\s*(ms|s|rpm|%|pp|b|kb|mb|gb|×)?(?![a-z])/i)
  if (m && /\d/.test(m[2])) {
    let n = parseFloat(m[2].replace(/,/g, ""))
    if (Number.isNaN(n)) return text.toLowerCase()
    if (m[1] === "-" || m[1] === "−") n = -n
    const unit = (m[3] || "").toLowerCase()
    return n * (UNITS[unit] || 1)
  }
  return text.toLowerCase()
}
