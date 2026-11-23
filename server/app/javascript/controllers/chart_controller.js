import { Controller } from "@hotwired/stimulus"

// Renders a Chart.js chart from a JSON config produced by ApplicationHelper#chart.
// Time charts support drag-to-zoom: dragging across the plot reloads the page
// with ?from=&to= for that window, so every drill-down keeps the zoomed range.
export default class extends Controller {
  static values = { config: Object, title: String }

  connect() {
    this.redraw = () => { this.chart?.destroy(); this.render() }
    window.addEventListener("nf:themechange", this.redraw)
    // A morphing auto-refresh resets the canvas' size attributes (blanking it)
    // and may bring new data: always redraw from the current config.
    document.addEventListener("turbo:morph", this.redraw)
    this.media = matchMedia("(prefers-color-scheme: dark)")
    this.media.addEventListener?.("change", this.redraw)
    this.render()
  }

  render() {
    if (!window.Chart) return
    const cfg = this.configValue
    const css = getComputedStyle(document.documentElement)
    const fg = css.getPropertyValue("--text-3").trim() || "#64748b"
    const grid = css.getPropertyValue("--grid").trim() || "rgba(100,116,139,.15)"
    const tooltipBg = css.getPropertyValue("--tooltip-bg").trim() || "#0f172a"
    const isTime = cfg.x === "time"
    const spanDays = isTime && cfg.labels.length > 1 ? (cfg.labels[cfg.labels.length - 1] - cfg.labels[0]) / 86400 : 0
    const unit = cfg.unit

    const datasets = cfg.datasets.map((d) => {
      const base = { label: d.label, data: isTime ? d.data.map((v, i) => ({ x: cfg.labels[i], y: v })) : d.data }
      const color = d.color || "#6366f1"
      if (cfg.type === "bar") {
        return { ...base, backgroundColor: color, borderRadius: 3, maxBarThickness: 22 }
      }
      return {
        ...base,
        borderColor: color,
        backgroundColor: cfg.stacked ? color + "d9" : color + "1f",
        fill: cfg.stacked ? (cfg.datasets.length > 1 ? "stack" : "origin") : cfg.type === "area" ? "origin" : false,
        borderWidth: cfg.stacked ? 0 : 1.75,
        // Lines hide their points, so a value with no neighbours would be invisible.
        pointRadius: (ctx) => (isIsolated(d.data, ctx.dataIndex) ? 3 : 0),
        pointHitRadius: 6,
        tension: 0.25,
        spanGaps: true,
      }
    })

    const fmtX = (v) => {
      const d = new Date(v * 1000)
      if (spanDays > 1.5) return d.toLocaleDateString([], { month: "short", day: "numeric" }) + " " + d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
      return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
    }

    this.chart = new window.Chart(this.element, {
      type: cfg.type === "bar" ? "bar" : "line",
      data: { labels: isTime ? undefined : cfg.labels, datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        // Chart.js only forwards these to plugins; the zoom brush needs down/up.
        events: ["mousemove", "mouseout", "click", "touchstart", "touchmove", "mousedown", "mouseup"],
        parsing: isTime ? { xAxisKey: "x", yAxisKey: "y" } : undefined,
        interaction: { mode: "index", intersect: false },
        scales: {
          x: isTime
            ? { type: "linear", min: cfg.labels[0], max: cfg.labels[cfg.labels.length - 1], grid: { display: false }, border: { color: grid }, ticks: { color: fg, maxTicksLimit: 6, callback: fmtX, font: { size: 11 } } }
            : { stacked: cfg.stacked, grid: { display: false }, border: { color: grid }, ticks: { color: fg, maxRotation: 0, autoSkip: true, font: { size: 11 } } },
          y: { stacked: cfg.stacked, beginAtZero: true, grid: { color: grid }, border: { display: false }, ticks: { color: fg, maxTicksLimit: 4, padding: 6, callback: (v) => format(v, unit), font: { size: 11 } } },
        },
        plugins: {
          legend: {
            display: cfg.legend !== false && cfg.datasets.length > 1, position: "bottom", align: "start",
            labels: {
              color: fg, boxWidth: 8, boxHeight: 8, padding: 10, usePointStyle: true, pointStyle: "rectRounded", font: { size: 11 },
              // Long segment names would push the plot out of the card; the tooltip keeps the full name.
              generateLabels: (chart) =>
                window.Chart.defaults.plugins.legend.labels.generateLabels(chart).map((l) => ({ ...l, text: shorten(l.text, 34) })),
            },
          },
          tooltip: {
            backgroundColor: tooltipBg, padding: 10, cornerRadius: 8, boxPadding: 4, usePointStyle: true,
            titleFont: { size: 12, weight: "600" }, bodyFont: { size: 12 }, footerFont: { size: 12 },
            callbacks: {
              title: (items) => (isTime && items.length ? new Date(items[0].parsed.x * 1000).toLocaleString() : items[0]?.label),
              label: (item) => `${item.dataset.label}: ${format(item.parsed.y, unit)}`,
              footer: (items) => (cfg.stacked && items.length > 1 ? `Total: ${format(items.reduce((s, i) => s + (i.parsed.y || 0), 0), unit)}` : ""),
            },
          },
        },
      },
      plugins: [...(cfg.zoom ? [this.brushPlugin(cfg)] : []), ...(cfg.markers?.length ? [markerPlugin(cfg.markers, fg)] : [])],
    })
  }

  disconnect() {
    window.removeEventListener("nf:themechange", this.redraw)
    document.removeEventListener("turbo:morph", this.redraw)
    this.media?.removeEventListener?.("change", this.redraw)
    this.chart?.destroy()
    this.chart = null
  }

  brushPlugin(cfg) {
    const state = { start: null, end: null }
    return {
      id: "brush",
      afterEvent: (chart, args) => {
        const e = args.event
        const area = chart.chartArea
        const inside = e.x >= area.left && e.x <= area.right
        if (e.type === "mousedown" && inside) {
          state.start = e.x
          state.end = e.x
        } else if (e.type === "mousemove" && state.start !== null) {
          state.end = Math.min(Math.max(e.x, area.left), area.right)
          args.changed = true
        } else if (e.type === "mouseup" && state.start !== null) {
          state.end = Math.min(Math.max(e.x, area.left), area.right)
          const [a, b] = [state.start, state.end].sort((x, y) => x - y)
          state.start = null
          args.changed = true
          if (b - a < 8) return
          const scale = chart.scales.x
          const from = Math.floor(scale.getValueForPixel(a))
          const to = Math.ceil(scale.getValueForPixel(b)) + cfg.step
          const url = new URL(window.location.href)
          url.searchParams.delete("range")
          url.searchParams.set("from", from)
          url.searchParams.set("to", to)
          window.Turbo ? window.Turbo.visit(url.toString()) : (window.location = url.toString())
        } else if (e.type === "mouseout") {
          state.start = null
          args.changed = true
        }
      },
      beforeDatasetsDraw: (chart) => {
        if (state.start === null || state.start === state.end) return
        const { ctx, chartArea } = chart
        ctx.save()
        ctx.fillStyle = "rgba(99,102,241,0.15)"
        ctx.fillRect(Math.min(state.start, state.end), chartArea.top, Math.abs(state.end - state.start), chartArea.bottom - chartArea.top)
        ctx.restore()
      },
    }
  }
}

// Dashed vertical lines for deployments, labelled with the revision.
function markerPlugin(markers, color) {
  return {
    id: "markers",
    afterDatasetsDraw(chart) {
      const { ctx, chartArea, scales } = chart
      ctx.save()
      ctx.strokeStyle = "#16a34a"
      ctx.fillStyle = color
      ctx.setLineDash([4, 3])
      ctx.font = "10px ui-sans-serif, system-ui"
      let lastLabelEnd = -Infinity
      markers.forEach((m) => {
        const x = scales.x.getPixelForValue(m.x)
        if (x < chartArea.left || x > chartArea.right) return
        ctx.beginPath()
        ctx.moveTo(x, chartArea.top)
        ctx.lineTo(x, chartArea.bottom)
        ctx.stroke()
        // Deploys close together share one label rather than overprinting.
        const width = ctx.measureText(m.label).width
        const lx = Math.min(x + 3, chartArea.right - width)
        if (lx > lastLabelEnd + 4) {
          ctx.fillText(m.label, lx, chartArea.top + 10)
          lastLabelEnd = lx + width
        }
      })
      ctx.restore()
    },
  }
}

function shorten(text, max) {
  return text.length > max ? text.slice(0, max - 1) + "…" : text
}

function isIsolated(data, i) {
  const has = (j) => j >= 0 && j < data.length && data[j] !== null && data[j] !== undefined
  return has(i) && !has(i - 1) && !has(i + 1)
}

function format(v, unit) {
  if (v === null || v === undefined || Number.isNaN(v)) return "–"
  switch (unit) {
    case "ms":
      if (v >= 1000) return (v / 1000).toFixed(v >= 10000 ? 0 : 1) + " s"
      return (v >= 10 ? Math.round(v) : Math.round(v * 10) / 10) + " ms"
    case "rpm":
      return (v >= 100 ? Math.round(v) : Math.round(v * 100) / 100) + " rpm"
    case "%":
      return Math.round(v * 100) / 100 + "%"
    case "apdex":
      return v.toFixed(2)
    default:
      return v >= 1000 ? Math.round(v).toLocaleString() : Math.round(v * 100) / 100
  }
}
