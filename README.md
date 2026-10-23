# TrueCommit

A GitHub-style contribution heatmap in your terminal, built from **local** git history: every branch, every
commit, pushed or not. Styled after Claude Code's `/stats` screen. One PowerShell file, no dependencies besides git.

```
    Oct    Dec Jan Feb Mar  Apr May  Jun Jul Aug  Sep Oct
    ·····································▓░░▒·▒▓░▓▒▒▓▓·░
Mon ·····································██·░░▒▒▓░█·░░·▓·
    ...
    Less ░ ▒ ▓ █ More

All time · Last 7 days · Last 30 days

Favorite repo: RobloxTowergame    Total commits: 440

Repos: 5/7                        Unpushed: 48
Active days: 84/110               Longest streak: 17 days
Most active day: Jul 11           Current streak: 2 days
First commit Jul 6, 2026 · Busiest day 24 commits · 5.2 commits per active day

48 of your commits exist only on this machine - GitHub has never seen them
```

## Install

From the PowerShell Gallery:

```powershell
Install-Module TrueCommit -Scope CurrentUser
```

Or straight from GitHub:

```powershell
irm https://raw.githubusercontent.com/nyad-dev/TrueCommit/main/install.ps1 | iex
```

Works in Windows PowerShell 5.1 and PowerShell 7. Needs a terminal with true-color support (Windows Terminal).

## Use

```powershell
truecommit                    # this repo, or every repo below the current folder
truecommit D:\code            # every repo below D:\code
truecommit -All               # every repo under your user folder (or $env:TRUECOMMIT_ROOT)
truecommit -Range 30d         # stats for the last 30 days (also: 7d, all)
truecommit -Author me@x.com   # someone else's commits / a different email
```

Commits are matched by each repo's `user.email` (falling back to your global one), de-duplicated across
clones, and merge commits are skipped. "Unpushed" counts your commits that no remote-tracking branch contains.
