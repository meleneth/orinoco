# D2R visual-observer fixture collection (Codex task)

You are working in **meleneth/orinoco**, on the current branch. Your objective is to **collect the first real, labeled Diablo II: Resurrected screenshot corpus from the user's running OBS capture**, sufficient to start implementing deterministic visual detectors. This is a data-collection task, not a request to implement the whole recognizer.

Read `AGENTS.md`, `railsapp/AGENTS.md`, `docs/visual-observer.md`, and the existing WOS fixture capture skill at `.codex/skills/screenshot-a-new-fixture/SKILL.md` before changing anything.

## Non-negotiable operating rules

- Observe **only** through OBS screenshots/OBS WebSocket; do not inspect D2R memory, inject code, hook the process, read packets, or automate gameplay inputs.
- **Do not touch the live OBS scene/source transforms**. Use the configured game source or a temporary calibration scene with a source reference. Never switch the program scene or disrupt the stream without explicit user permission.
- The user is running Linux/Debian on a Framework 16, typically at **1920x1200**, not the Windows/MSYS environment from the WOS helper. Implement a Linux-compatible capture workflow, preferably using existing Rails runner and `ObsBridge::ObswsSessionRunner`. Do not blindly run the PowerShell helper.
- Capture actual native-detail source frames when possible. `GetSourceScreenshot` imageWidth/imageHeight **resize**; they do not crop. Keep screenshot pixel dimensions, OBS base/output dimensions and any configured crop/transform separate in the manifest. Preserve aspect ratio.
- **Never invent ground-truth labels.** A screenshot alone does not prove the exact item or boss. Ask the user to confirm ambiguous labels, record `unknown`, and include confidence/provenance. Capture both positive and negative examples.
- No growing screenshot queue. Capture on demand during guided calibration. For a short timed sequence, bound duration, sampling interval, and total images.
- Keep raw screenshots local by default. Do not commit dozens of megabytes of images, private desktop content, Twitch chat, credentials, or unrelated sources. Only promote reviewed, sanitized representative fixtures to Git; ask before adding large binary datasets. Never delete existing fixtures or overwrite a user's captures.
- Strict bash scripts must use `set -euo pipefail`. Errors should fail loudly, not be disguised by fallback screenshots.

## Deliverables

1. A repeatable **interactive Linux-friendly capture command** (script or Rails runner task) using existing OBS connection configuration and the `GetSourceScreenshot` command path. Accept a named state, optional source, optional frame count, sampling interval, and output directory. Do not require OBS program-scene switching. Avoid exposing OBS connection credentials.
2. Store raw frames in a gitignored collection directory, such as `railsapp/tmp/d2r-captures/<session-id>/`, and provide a manifest in JSON with: schema version, capture time (UTC), OBS source/scene, frame dimensions, native/source dimensions if available, base/output video dimensions, game/window resolution when verified, calibration region name/geometry if known, expected UI state, manually confirmed labels, and file SHA-256. Explicitly mark unavailable fields `null` rather than guessing.
3. Provide a **guided capture checklist** that tells the user what to open in the game, then waits for explicit confirmation before capturing. Do not try to drive D2R. Capture a short burst (e.g. 3 frames one second apart) per state for temporal variation, plus an uncluttered baseline screenshot.
4. Add a **validation tool** that checks all manifest paths, PNG/JPEG readability and dimensions, hashes, state labels, duplicate frames, and that at least one useful positive/negative pair exists for each initially targeted detector. Keep machine-detected results distinct from user-verified labels.
5. Add focused automated tests for capture manifest generation, naming, bounds, and validation with fake OBS responses. Tests must not require live OBS, AWS, or D2R.
6. Document exact invocation, expected output directories, and how to promote *selected* labeled captures to `railsapp/spec/fixtures/files/d2r/` after review. Report what was **actually captured** versus what still needs the user's cooperation.

## Initial guided states (prioritize useful data, not sheer quantity)

Capture these states if the user can produce them in the current play session:

| State key | User opens/shows | Detector target |
| --- | --- | --- |
| `gameplay_idle` | Ordinary gameplay with no panel | Negative baseline, HUD geometry |
| `area_banner` | Enter a new zone while area title appears | Area name and transition |
| `waypoint_or_portal` | Waypoint/map/portal UI | Transition cues |
| `character_sheet` | Character screen with name, level, stats and resistances | Character profile |
| `skill_tree` | Current skill allocation panel | Build classification |
| `inventory_open` | Inventory with visible item grid | Panel classification |
| `item_tooltip_white` | Hover an unsocketed white item, ideally a Monarch | Tooltip detection / quality |
| `item_tooltip_magic` | Hover blue crafting item, ideally Bramble Mitts | Magic-item recognition |
| `item_tooltip_rune` | Hover a rune | Rune tooltip parsing |
| `stash_runes` | Rune stash tab fully visible | Rune quantity reconciliation |
| `stash_other` | Non-rune stash tab | Negative for rune-tab classifier |
| `loading_screen` | Natural loading transition | Run lifecycle |
| `boss_visible` | Andariel (or other target) alive if convenient | Boss recognizer |
| `boss_dead` | Boss corpse/loot aftermath if convenient | Kill recognition |
| `death_screen` | Only if it naturally happens | Death recognition; do NOT ask user to die |

If a state isn't available, leave it marked **missing**; do not fabricate an example. For short-lived states such as banners, allow user-controlled burst capture around the next natural transition with a strict max duration, and report sampling miss risk. For tooltips, capture a few distinct pointer positions and at least one tooltip-closed negative.

## Geometry and calibration

- Use existing OBS `GetSceneItemTransform` and `GetVideoSettings` support where appropriate.
- OBS cropLeft/cropRight/cropTop/cropBottom are **source-side cuts**; positionX/positionY refer to scene placement. Don't conflate the two.
- Persist source-relative normalized rectangles **and** the raw OBS transform as evidence.
- If OBS has no pixel-region screenshot API, capture source frames then crop locally for classifier fixtures; optionally benchmark an OBS-side cropped source later. Do not crop away the original evidence.
- Add metadata indicating OBS scaling and UI/window aspect-ratio differences; no hardcoded assumption that every user will be at 1080p.

## Acceptance criteria

- One command can produce a labeled capture for a state the user has opened, using OBS without playing the game for them.
- A guided session can collect multiple states without overwriting files.
- Every frame is traceable to a manifest entry and has verifiable image dimensions/hash.
- The validator rejects corrupted frames, unknown/invalid state labels, hash mismatches, and inconsistent geometry.
- Focused tests pass; any inability to run the tests is reported plainly.
- Give the user a compact summary of captured states, missing states, sizes, and the command to resume collection.
- Do **not** claim D2R recognition or run tracking works until actual detectors and end-to-end tests exist.

Aim to finish with a usable collection instrument and real initial samples if the local OBS/game are accessible. If OBS is unavailable in the execution environment, implement and test the capture tool using fakes, then clearly state the exact command the user can run locally for the guided collection.
