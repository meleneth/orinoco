import { Controller } from "@hotwired/stimulus"

// The projection stores timestamps, not a ticking Redis counter. The browser
// renders elapsed time from server-origin event timestamps.
export default class extends Controller {
  static targets = ["state", "stream", "elapsed", "level", "area", "difficulty", "terrorZones", "run", "step", "splits", "historyToggle", "historyPanel", "historyPage", "historyList", "historyDetails"]
  static values = { url: String, historyUrl: String }

  connect() {
    this.historyPageNumber = 1
    this.historyTotal = 0
    this.revision = 0
    this.active = true
    this.readState()
    this.clock = setInterval(() => this.tick(), 250)
    this.connectionObserver = new MutationObserver(() => this.connectionChanged())
    this.connectionObserver.observe(this.streamTarget, { attributes: true, attributeFilter: ["connected"] })
    this.connectionChanged()
  }

  disconnect() {
    this.active = false
    clearInterval(this.clock)
    this.connectionObserver?.disconnect()
    this.syncRequest?.abort()
  }

  stateTargetConnected() {
    if (this.active) this.readState()
  }

  readState() {
    if (!this.hasStateTarget) return
    this.revision += 1
    this.state = JSON.parse(this.stateTarget.textContent)
    this.render()
  }

  connectionChanged() {
    if (this.streamTarget.hasAttribute("connected")) {
      this.refresh()
    } else {
      this.syncRequest?.abort()
    }
  }

  async refresh() {
    this.syncRequest?.abort()
    const request = new AbortController()
    this.syncRequest = request
    const revision = this.revision
    try {
      const response = await fetch(this.urlValue, {
        cache: "no-store",
        headers: { Accept: "text/vnd.turbo-stream.html" },
        signal: request.signal
      })
      if (!response.ok) throw new Error(`D2R state HTTP ${response.status}`)
      const html = await response.text()
      if (this.active && !request.signal.aborted && revision === this.revision) {
        // Use the same server-rendered fragment as a normal live broadcast.
        const template = document.createElement("template")
        template.innerHTML = html
        const fragment = template.content.querySelector("template")?.content
        const target = this.element.querySelector("#d2r_live_projection")
        if (fragment && target) target.replaceWith(fragment.cloneNode(true))
      }
    } catch (error) {
      if (error.name !== "AbortError") console.warn("[d2r-run] projection unavailable", error)
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


  toggleHistory() {
    const opened = this.historyPanelTarget.classList.toggle("hidden") === false
    this.historyToggleTarget.textContent = opened ? "Hide runs" : "Browse runs"
    if (opened) this.loadHistory()
  }

  previousPage() {
    if (this.historyPageNumber <= 1) return
    this.historyPageNumber -= 1
    this.loadHistory()
  }

  nextPage() {
    if (this.historyPageNumber * 20 >= this.historyTotal) return
    this.historyPageNumber += 1
    this.loadHistory()
  }

  async loadHistory() {
    try {
      const url = new URL(this.historyUrlValue, window.location.href)
      url.searchParams.set("page", String(this.historyPageNumber))
      url.searchParams.set("limit", "20")
      const response = await fetch(url, { cache: "no-store" })
      if (!response.ok) throw new Error(`Run history HTTP ${response.status}`)
      const result = await response.json()
      this.historyTotal = result.total
      this.historyPageTarget.textContent = `Page ${result.page} · ${result.total} runs`
      this.historyListTarget.replaceChildren(...result.runs.map(run => {
        const item = document.createElement("li")
        const button = document.createElement("button")
        button.type = "button"
        button.className = "w-full rounded border border-slate-700 p-2 text-left hover:border-cyan-600"
        const runes = (run.loot_sightings || []).filter(sighting => sighting.kind === "rune")
        const uniques = (run.loot_sightings || []).filter(sighting => sighting.kind === "unique")
        button.textContent = `${new Date(run.started_at).toLocaleString()} · ${run.run_kind || "Unclassified"} · ${run.outcome?.replaceAll("_", " ") || "unknown"} · ${run.area || "Unknown area"} · ${this.format(run.duration_seconds)} · ${runes.length} runes · ${uniques.length} uniques`
        button.addEventListener("click", () => this.showHistoryRun(run))
        item.append(button)
        return item
      }))
    } catch (error) {
      this.historyDetailsTarget.textContent = `Could not load run history: ${error.message}`
    }
  }

  async showHistoryRun(summary) {
    this.historyDetailsTarget.textContent = "Loading run details..."
    let run
    try {
      const response = await fetch(`${this.historyUrlValue}/${summary.id}`, { cache: "no-store" })
      if (!response.ok) throw new Error(`Run detail HTTP ${response.status}`)
      run = await response.json()
    } catch (error) {
      this.historyDetailsTarget.textContent = `Unable to load run details: ${error.message}`
      return
    }
    const details = [
      `Game: ${run.game_id}`,
      `Started: ${new Date(run.started_at).toLocaleString()}`,
      `Ended: ${run.ended_at ? new Date(run.ended_at).toLocaleString() : "In progress"}`,
      `Run: ${run.run_kind || "Unclassified"}${run.repeated ? " (repeat)" : ""}`,
      `Outcome: ${run.outcome?.replaceAll("_", " ") || "unknown"}`,
      `Confidence: ${run.run_confidence == null ? "Not classified" : `${Math.round(run.run_confidence * 100)}%`}`,
      `Evidence: ${(run.run_evidence || []).join(" → ") || "None"}`,
      `Level: ${run.character_level ?? "?"} · Difficulty: ${run.difficulty || "?"}`,
      `Area: ${run.area || "Unknown"}`,
      "Splits:",
      ...(run.steps || []).map(step => `  ${step.name}: ${this.format(step.seconds || 0)}`),
      "Rune sightings:",
      ...(run.loot_sightings || []).filter(loot => loot.kind === "rune").map(loot => `  ${new Date(loot.at).toLocaleTimeString()} ${loot.name} (sighted)`),
      "Unique item candidates:",
      ...(run.loot_sightings || []).filter(loot => loot.kind === "unique").map(loot => `  ${new Date(loot.at).toLocaleTimeString()} ${loot.name} (unverified)`),
      "Detection events:",
      ...(run.events || []).slice().reverse().map(e => `  ${new Date(e.at).toLocaleTimeString()} ${e.type}`)
    ]
    this.historyDetailsTarget.textContent = details.join("\n")
  }

  format(seconds) {
    const total = Math.floor(seconds)
    return `${String(Math.floor(total / 3600)).padStart(2, "0")}:${String(Math.floor(total % 3600 / 60)).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`
  }
}
