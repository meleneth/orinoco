import { Controller } from "@hotwired/stimulus"

let lastPlayedVolleyId = null
const SVG_NS = "http://www.w3.org/2000/svg"
const SHOT_DURATION_MS = 1650

export default class extends Controller {
  static targets = ["effects", "volley"]

  connect() {
    this.timeouts = []
    this.animationFrames = []
    this.playCurrentVolley()
  }

  disconnect() {
    this.timeouts.forEach((timeout) => clearTimeout(timeout))
    this.animationFrames.forEach((frame) => cancelAnimationFrame(frame))
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
      this.after(shotIndex * 260, () => this.playShot(shot))
    })
  }

  playShot(shot) {
    const points = shot.points || []
    if (points.length === 0) return

    const group = document.createElementNS(SVG_NS, "g")
    const traceGlow = this.polyline(points, "#f3a833", 14, 0.24)
    const traceCore = this.polyline(points, "#fff3b0", 5, 0.78)
    const shellGlow = this.circle(points[0].x, points[0].y, 18, "#f3a833")
    const shell = this.circle(points[0].x, points[0].y, 7, "#ffffff")
    shellGlow.setAttribute("opacity", "0.45")
    group.append(traceGlow, traceCore, shellGlow, shell)
    this.effectsTarget.append(group)

    this.playMuzzleFlash(points[0])
    this.seedSmoke(group, points)

    const startedAt = performance.now()
    const step = (now) => {
      const ratio = Math.min((now - startedAt) / SHOT_DURATION_MS, 1)
      const point = this.pointAt(points, ratio)
      shell.setAttribute("cx", point.x)
      shell.setAttribute("cy", point.y)
      shellGlow.setAttribute("cx", point.x)
      shellGlow.setAttribute("cy", point.y)
      traceCore.setAttribute("stroke-dashoffset", this.traceOffset(traceCore, ratio))
      traceGlow.setAttribute("stroke-dashoffset", this.traceOffset(traceGlow, ratio))

      if (ratio < 1) {
        this.animationFrames.push(requestAnimationFrame(step))
      } else {
        shell.remove()
        shellGlow.remove()
        this.playImpacts(shot)
        this.after(1200, () => group.remove())
      }
    }

    this.prepareTrace(traceCore)
    this.prepareTrace(traceGlow)
    this.animationFrames.push(requestAnimationFrame(step))
  }

  pointAt(points, ratio) {
    return points[Math.min(Math.floor(ratio * (points.length - 1)), points.length - 1)]
  }

  prepareTrace(line) {
    const length = line.getTotalLength ? line.getTotalLength() : 1800
    line.dataset.length = length
    line.setAttribute("stroke-dasharray", length)
    line.setAttribute("stroke-dashoffset", length)
  }

  traceOffset(line, ratio) {
    const length = Number.parseFloat(line.dataset.length || "1800")
    return length * (1 - ratio)
  }

  seedSmoke(group, points) {
    const stride = Math.max(Math.floor(points.length / 10), 1)
    points.forEach((point, index) => {
      if (index % stride !== 0) return

      this.after(index * (SHOT_DURATION_MS / points.length), () => {
        const puff = this.circle(point.x, point.y, 8 + (index % 4) * 3, index % 2 === 0 ? "#d7dde1" : "#8a9299")
        puff.setAttribute("opacity", "0.52")
        group.prepend(puff)
        puff.animate(
          [
            { r: Number.parseFloat(puff.getAttribute("r")), opacity: 0.52, transform: "translateY(0px)" },
            { r: 34, opacity: 0, transform: "translateY(-28px)" }
          ],
          { duration: 1150, easing: "cubic-bezier(.2,.8,.2,1)" }
        )
        this.after(1200, () => puff.remove())
      })
    })
  }

  playMuzzleFlash(point) {
    const flash = this.circle(point.x, point.y, 6, "#fff3b0")
    flash.setAttribute("stroke", "#e98537")
    flash.setAttribute("stroke-width", "4")
    this.effectsTarget.append(flash)
    flash.animate(
      [
        { r: 6, opacity: 1 },
        { r: 42, opacity: 0 }
      ],
      { duration: 260, easing: "cubic-bezier(.2,.8,.2,1)" }
    )
    this.after(300, () => flash.remove())
  }

  playImpacts(shot) {
    ;(shot.explosions || []).forEach((explosion) => this.playExplosion(explosion))
    ;(shot.damage_events || []).forEach((event) => this.playDamage(event))
  }

  playExplosion(explosion) {
    const burst = this.circle(explosion.x, explosion.y, 8, "#e98537")
    const shockwave = this.circle(explosion.x, explosion.y, 4, "none")
    burst.setAttribute("stroke", "#fff3b0")
    burst.setAttribute("stroke-width", "6")
    burst.setAttribute("opacity", "0.92")
    shockwave.setAttribute("stroke", "#ffffff")
    shockwave.setAttribute("stroke-width", "5")
    shockwave.setAttribute("opacity", "0.72")
    this.effectsTarget.append(burst, shockwave)

    burst.animate(
      [
        { r: 8, opacity: 0.92 },
        { r: explosion.radius || 56, opacity: 0 }
      ],
      { duration: 760, easing: "cubic-bezier(.2,.8,.2,1)" }
    )
    shockwave.animate(
      [
        { r: 4, opacity: 0.72 },
        { r: (explosion.radius || 56) * 1.35, opacity: 0 }
      ],
      { duration: 920, easing: "cubic-bezier(.2,.8,.2,1)" }
    )
    this.after(960, () => {
      burst.remove()
      shockwave.remove()
    })
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
      { duration: 900, easing: "cubic-bezier(.2,.8,.2,1)" }
    )
    this.after(940, () => label.remove())
  }

  polyline(points, stroke, width, opacity) {
    const line = document.createElementNS(SVG_NS, "polyline")
    line.setAttribute("points", points.map((point) => `${point.x},${point.y}`).join(" "))
    line.setAttribute("fill", "none")
    line.setAttribute("stroke", stroke)
    line.setAttribute("stroke-width", width)
    line.setAttribute("stroke-linecap", "round")
    line.setAttribute("stroke-linejoin", "round")
    line.setAttribute("opacity", opacity)
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
