# RhysCheck

Read-only Windows PC fault check for [Claude Code](https://code.claude.com/docs/en/overview). Describe the problem, get a short diagnostic report: verdict, findings, and fixes.

```
/rhyscheck screen flickering
```

## 1. Install Claude Code

Open **PowerShell** and run:

```powershell
irm https://claude.ai/install.ps1 | iex
```

Open a new PowerShell window, then start Claude Code and sign in when prompted (first run only):

```powershell
claude
```

## 2. Install RhysCheck

In PowerShell:

```powershell
irm https://raw.githubusercontent.com/Rhyyslloyd/rhyscheck/main/install.ps1 | iex
```

Or, from inside Claude Code, paste:

```
Install the RhysCheck skill by running this in PowerShell: irm https://raw.githubusercontent.com/Rhyyslloyd/rhyscheck/main/install.ps1 | iex
```

Restart Claude Code if `/rhyscheck` doesn't appear straight away.

## 3. Use it

```
/rhyscheck screen flickering
/rhyscheck pc randomly restarting
/rhyscheck wifi keeps dropping
/rhyscheck
```

With no issue given, it runs a general health check. Run your terminal as Administrator for full coverage; checks that need admin are flagged in the report.

## How it works

- `skills/rhyscheck/SKILL.md` tells Claude how to investigate and how to format the report.
- `skills/rhyscheck/scripts/checks.ps1` collects the diagnostics: drivers, event logs, monitors, disks, network and more. It's read-only and can be run on its own:

  ```powershell
  .\checks.ps1 -Category baseline,display -Days 14
  ```

  Categories: `baseline`, `display`, `performance`, `crash`, `network`, `audio`, `storage`, `usb`, `boot`, `all`.

Nothing on the PC is changed during a check. Claude offers fixes at the end and applies one only when you pick it.

## Update or remove

Update: re-run the install line.

Remove:

```powershell
Remove-Item -Recurse "$env:USERPROFILE\.claude\skills\rhyscheck"
```
