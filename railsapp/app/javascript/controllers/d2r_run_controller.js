import { Controller } from "@hotwired/stimulus"

// The projection stores timestamps, not a ticking Redis counter. The browser
// renders elapsed time from server-origin event timestamps.
export default class extends Controller {
  static targets = ["elapsed", "level", "area", "difficulty", "terrorZones", "run", "step", "splits"]
  static values = { url: String }

  connect() {
    this.tick()
    this.refresh()
    this.poll = setInterval(() => this.refresh(), 1000)
    this.clock = setInterval(() => this.tick(), 250)
  }

  disconnect() {
    clearInterval(this.poll)
    clearInterval(this.clock)
  }

  async refresh() {
    try {
      const response = await fetch(this.urlValue, { cache: "no-store" })
      if (!response.ok) throw new Error(`D2R state HTTP ${response.status}`)
      this.state = await response.json()
      this.render()
    } catch (error) {
      console.warn("[d2r-run] projection unavailable", error)
    }
  }

  render() {
    const state = this.state || {}
    this.levelTarget.textContent = state.level ?? "?"
    this.areaTarget.textContent = state.area || "Unknown area"
    this.difficultyTarget.textContent = state.difficulty || "?"
    this.terrorZonesTarget.textContent = state.terror_zones?.join(" · ") || "No active zones"
    const run = state.run
    this.runTarget.textContent = run ? `${run.kind}${run.repeated ? " (repeat)" : ""}` : "Unclassified run"
    this.stepTarget.textContent = run?.step?.name || "No active step"
    this.splitsTarget.replaceChildren(...(run?.steps || []).map(step => {
      const row = document.createElement("li")
      const prior = run.previous_steps?.find(previous => previous.name === step.name)
      const delta = prior ? ` (${step.seconds >= prior.seconds ? "+" : ""}${(step.seconds - prior.seconds).toFixed(1)}s)` : ""
      row.textContent = `${step.name}: ${this.format(step.seconds)}${delta}`
      return row
    }))
    this.tick()
  }

  tick() {
    const game = this.state?.game
    const end = game?.ended_at ? Date.parse(game.ended_at) : Date.now()
    this.elapsedTarget.textContent = game?.started_at
      ? this.format(Math.max(0, (end - Date.parse(game.started_at)) / 1000))
      : "00:00"
    const step = this.state?.run?.step
    if (step) this.stepTarget.textContent = `${step.name} · ${this.format(Math.max(0, (Date.now() - Date.parse(step.started_at)) / 1000))}`
  }

  format(seconds) {
    const total = Math.floor(seconds)
    return `${String(Math.floor(total / 3600)).padStart(2, "0")}:${String(Math.floor(total % 3600 / 60)).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`
  }
}
