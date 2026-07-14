---
name: screenshot-a-new-fixture
description: Capture the current OBS/WOS screenshot in the Orinoco repo, save it locally, promote it into railsapp/spec/fixtures/files/wos, and run the WOS recognizer summary. Use when the user asks to grab a screenshot as a fixture, add the latest WOS frame to the test corpus, or create a new screenshot fixture for recognizer tuning.
---

# Screenshot A New Fixture

Use this skill in the Orinoco repo when the user wants the current Words on Stream frame saved as a new test fixture.

## Workflow

1. Run `scripts/screenshot-wos-fixture.ps1` from the repo root.
2. Pass `-Name <fixture_base_name>` only when the user gives a stable name; otherwise let the script timestamp it.
3. Report both paths:
   - `railsapp/tmp/<name>.png`
   - `railsapp/spec/fixtures/files/wos/<name>.png`
4. Include the recognizer summary printed by the script: letters, remaining-word summaries, solved words, and players.
5. If recognition is wrong, do not edit fixture truth silently. Ask for or use the user-provided truth labels, then update specs separately.

## Command

```powershell
.\.codex\skills\screenshot-a-new-fixture\scripts\screenshot-wos-fixture.ps1
```

With a stable name:

```powershell
.\.codex\skills\screenshot-a-new-fixture\scripts\screenshot-wos-fixture.ps1 -Name live_sahtnk_answers
```

## Notes

- The script uses `railsapp/dev.sh runner`, so run it from the repo root in this Windows/MSYS workspace.
- It captures the configured WOSBrain screenshot source from `AffordanceConfig.fetch!(:wos_brain).screenshot_source_name`.
- It writes the fixture into `railsapp/spec/fixtures/files/wos`; this is the recognizer test corpus.
- VIPS optional-loader warnings are common in this workspace and are not capture failures when the script prints paths and JSON.