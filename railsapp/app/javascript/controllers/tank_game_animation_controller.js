import { Controller } from "@hotwired/stimulus"

let lastPlayedVolleyId = null
const SVG_NS = "http://www.w3.org/2000/svg"

export default class extends Controller {
  static targets = ["effects", "volley"]

  connect() {
    this.timeouts = []
    this.playCurrentVolley()
  }

  disconnect() {
    this.timeouts.forEach((timeout) => clearTimeout(timeout))
  }

  playCurrentVolley() {
    const volley = this.volley
    if (!volley.id || volley.id === lastPlayedVolleyId || this.expired(volley) || !this.hasEffectsTarget) return

    lastPlayedVolleyId = volley.id
    this.effectsTarget.replaceChildren()
    this.playShots(volley.shots || [])
  }

  get volley() {
    if (!this.hasVolleyTarget) return {}

    try {
      return JSON.parse(this.volleyTarget.textContent || "{}")
    } catch (_error) {
      return {}
    }
  }

  expired(volley) {
    if (!volley.expires_at) return false

    const expiresAt = Date.parse(volley.expires_at)
    return Number.isFinite(expiresAt) && expiresAt < Date.now()
  }

  playShots(shots) {
    shots.forEach((shot, shotIndex) => {
      this.after(shotIndex * 120, () => this.playShot(shot))
    })
  }

  playShot(shot) {
    const points = shot.points || []
    if (points.length === 0) return

    const trail = this.polyline(points)
    const shell = this.circle(points[0].x, points[0].y, 7, "#f3a833")
    this.effectsTarget.append(trail, shell)

    const duration = 720
    const startedAt = performance.now()
    const step = (now) => {
      const ratio = Math.min((now - startedAt) / duration, 1)
      const point = points[Math.min(Math.floor(ratio * (points.length - 1)), points.length - 1)]
      shell.setAttribute("cx", point.x)
      shell.setAttribute("cy", point.y)
      trail.setAttribute("opacity", 0.25 + (ratio * 0.6))

      if (ratio < 1) {
        requestAnimationFrame(step)
      } else {
        shell.remove()
        this.playImpacts(shot)
        this.after(500, () => trail.remove())
      }
    }
    requestAnimationFrame(step)
  }

  playImpacts(shot) {
    ;(shot.explosions || []).forEach((explosion) => this.playExplosion(explosion))
    ;(shot.damage_events || []).forEach((event) => this.playDamage(event))
  }

  playExplosion(explosion) {
    const burst = this.circle(explosion.x, explosion.y, 4, "#e98537")
    burst.setAttribute("stroke", "#f7f3b7")
    burst.setAttribute("stroke-width", "5")
    burst.setAttribute("opacity", "0.85")
    this.effectsTarget.append(burst)

    burst.animate(
      [
        { r: 4, opacity: 0.85 },
        { r: explosion.radius || 48, opacity: 0 }
      ],
      { duration: 520, easing: "cubic-bezier(.2,.8,.2,1)" }
    )
    this.after(560, () => burst.remove())
  }

  playDamage(event) {
    const label = document.createElementNS(SVG_NS, "text")
    label.setAttribute("x", event.x || 0)
    label.setAttribute("y", (event.y || 0) - 64)
    label.setAttribute("text-anchor", "middle")
    label.setAttribute("fill", "#ffffff")
    label.setAttribute("stroke", "#ac2847")
    label.setAttribute("stroke-width", "4")
    label.setAttribute("paint-order", "stroke")
    label.setAttribute("font-size", "34")
    label.setAttribute("font-weight", "800")
    label.textContent = `-${event.damage}`
    this.effectsTarget.append(label)

    label.animate(
      [
        { transform: "translateY(0px)", opacity: 1 },
        { transform: "translateY(-38px)", opacity: 0 }
      ],
      { duration: 780, easing: "cubic-bezier(.2,.8,.2,1)" }
    )
    this.after(820, () => label.remove())
  }

  polyline(points) {
    const line = document.createElementNS(SVG_NS, "polyline")
    line.setAttribute("points", points.map((point) => `${point.x},${point.y}`).join(" "))
    line.setAttribute("fill", "none")
    line.setAttribute("stroke", "#f6e8e0")
    line.setAttribute("stroke-width", "4")
    line.setAttribute("stroke-linecap", "round")
    line.setAttribute("opacity", "0.25")
    return line
  }

  circle(x, y, radius, fill) {
    const circle = document.createElementNS(SVG_NS, "circle")
    circle.setAttribute("cx", x)
    circle.setAttribute("cy", y)
    circle.setAttribute("r", radius)
    circle.setAttribute("fill", fill)
    return circle
  }

  after(delay, callback) {
    const timeout = setTimeout(callback, delay)
    this.timeouts.push(timeout)
  }
}