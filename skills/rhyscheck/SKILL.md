---
name: rhyscheck
description: Read-only Windows PC fault check for a named issue (e.g. /rhyscheck screen flickering). Runs bundled diagnostics and returns a short, professional report with the likely cause and recommended fixes.
argument-hint: "<issue, e.g. screen flickering>"
---

# RhysCheck — Windows PC fault check

Issue to investigate: **$ARGUMENTS**
If no issue was given, run a general health check.

The person running this wants the answer, not the process. Diagnose quietly, then deliver one tight report.

## Rules

- **Read-only.** During the check, never change settings, update or roll back drivers, uninstall, edit the registry, stop processes, restart, or delete anything. Fixes are offered at the end and applied only after the user says yes.
- No narration between tool calls. Run the checks, then write the report.
- If something comes back "needs admin", record it as such and move on. Don't try to elevate.

## Step 1 — Pick categories

Map the issue to one or two categories (always add `baseline`):

| Issue sounds like | Categories |
|---|---|
| Flicker, black screen, artefacts, monitor dropping out, resolution or scaling problems | `display` |
| Slow, freezing, lagging, high CPU or RAM, loud fans, overheating | `performance` |
| Blue screen, random restarts, shutting off, apps crashing | `crash` |
| No internet, Wi-Fi dropping, slow network, can't reach a share | `network` |
| No sound, crackling, mic not working | `audio` |
| Disk full, slow disk, drive missing, file errors | `storage` |
| USB, keyboard, mouse, webcam or Bluetooth not working or disconnecting | `usb` |
| Slow boot, slow login | `boot`, `performance` |
| Nothing given or "general check" | `crash`, `storage` |

## Step 2 — Run diagnostics

Run the bundled script once with all chosen categories (allow up to 3 minutes):

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_SKILL_DIR}/scripts/checks.ps1" -Category baseline,display
```

- Add `-Days 14` or `-Days 30` if the issue is intermittent or has been going on a while (default is 7 days).
- If the shell tool is PowerShell rather than Bash, use the same command; it works in both.
- `-Category all` runs everything. Use it only for a full health check.

If the output leaves a clear lead unexplained, run **one** round of targeted read-only follow-up commands (e.g. reading a specific event's full message, checking a registry value). Then stop digging and report.

## Step 3 — Report

Reply with exactly this shape, under about 200 words. No preamble, no list of commands run.

```
**RhysCheck — <Issue>**
<PC name> · <Windows edition and version> · <date, time>

**Verdict:** <one sentence: most likely cause> (Confidence: High / Medium / Low)

| Check | Result | Status |
|---|---|---|
| <check> | <short factual result> | OK / Warn / Fail |

**Recommended fix**
1. <least invasive first> — <"I can do this" or "You'll need to">
2. ...
3. ...

**To confirm:** <at most 2 questions, only if the answer would change the verdict>
```

- Table: 4–8 rows, most relevant first, only checks that bear on the issue.
- Use real values (driver version and date, event counts, timestamps), not vague words.
- If nothing abnormal turned up, say so plainly and give the next best lead, which is often hardware (cable, port, monitor, PSU, RAM).
- For display issues, ask whether the problem shows up in a screenshot or screen recording: if yes it's software or driver, if no it's cable, port, refresh rate or the monitor itself.

End with one line: `Reply with a fix number to apply it.`

## Step 4 — Applying fixes (only when asked)

Apply only the fix the user picked. Before anything hard to undo (driver change, registry edit, uninstall, disabling a service), state exactly what will change and confirm once. Afterwards, re-run the relevant category and report the before and after in two or three lines.
