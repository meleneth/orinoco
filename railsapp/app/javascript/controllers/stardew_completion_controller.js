import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["snapshot", "recent"]

  initialize() {
    this.previous = new Map()
    this.completed = new Map()
    this.scope = null
    this.timer = null
  }

  snapshotTargetConnected(snapshot) {
    const scope = snapshot.dataset.scope
    const tasks = JSON.parse(snapshot.textContent)
    if (scope !== this.scope) {
      this.previous.clear()
      this.completed.clear()
      this.scope = scope
    }
    const now = performance.now()
    const current = new Map(tasks.map(task => [task.id, task]))
    for (const task of tasks) {
      const prior = this.previous.get(task.id)
      const done = task.status === "complete" || task.status === "deferred"
      if (done && prior && prior.status !== "complete" && prior.status !== "deferred") {
        this.completed.set(task.id, { title: prior.title, expires: now + 10000 })
      } else if (!done) {
        this.completed.delete(task.id)
      }
    }
    this.previous = current
    this.renderRecent()
  }

  recentTargetConnected() {
    this.renderRecent()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  renderRecent() {
    clearTimeout(this.timer)
    if (!this.hasRecentTarget) return
    const now = performance.now()
    for (const [id, task] of this.completed) {
      if (task.expires <= now) this.completed.delete(id)
    }
    const fragment = document.createDocumentFragment()
    for (const task of this.completed.values()) {
      const row = document.createElement("p")
      row.className = "text-sm text-slate-400"
      const title = document.createElement("s")
      title.textContent = task.title
      row.append("✓ ", title)
      fragment.append(row)
    }
    this.recentTarget.replaceChildren(fragment)
    this.recentTarget.hidden = this.completed.size === 0
    if (this.completed.size) {
      const next = Math.min(...Array.from(this.completed.values(), task => task.expires))
      this.timer = setTimeout(() => this.renderRecent(), Math.max(0, next - now))
    }
  }
}
