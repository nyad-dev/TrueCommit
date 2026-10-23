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

**Any OS with PowerShell**, from the [PowerShell Gallery](https://www.powershellgallery.com/packages/TrueCommit):

```powershell
Install-Module TrueCommit -Scope CurrentUser
```

**Windows** without the Gallery (PowerShell 5.1 or 7):

```powershell
irm https://raw.githubusercontent.com/nyad-dev/TrueCommit/main/install.ps1 | iex
```

**Linux / macOS** (needs [PowerShell 7](https://aka.ms/install-powershell), e.g. `brew install powershell`).
This also adds a `truecommit` command to `~/.local/bin` so it runs straight from bash or zsh:

```sh
curl -fsSL https://raw.githubusercontent.com/nyad-dev/TrueCommit/main/install.sh | sh
```

Needs a terminal with true-color support (Windows Terminal, iTerm2, most Linux terminals).

## Use

```powershell
truecommit                    # this repo, or every repo below the current folder
truecommit D:\code            # every repo below D:\code
truecommit -All               # every repo under your user folder (or $env:TRUECOMMIT_ROOT)
truecommit -Range 30d         # stats for the last 30 days (also: 7d, all)
truecommit -Author me@x.com   # someone else's commits / a different email
truecommit -GitHub            # also count commits that are only on GitHub (made on other machines)
truecommit -Color green       # orange (default), green, blue, purple, pink, or any hex like #39d353
truecommit -Lines             # lines of code changed instead of commits
```

### Lines mode

`-Lines` colors the heatmap by lines changed (added + removed) and shows `Lines: +added -removed`.
It doesn't count what people rarely write by hand: binary files, data/asset formats (`.json`, `.obj`, `.gltf`,
`.svg`, `.csv`, `.rbxmx`, `.rbxlx`, ...), lockfiles, minified files, `vendor`/`third_party`/`node_modules`/`dist`/`build`
folders, and any single file with 5000+ changed lines in one commit. It has to diff every commit, so it is
slower than the commit view (about the time of your largest repo, since repos are read in parallel).

To keep a color, set it once in your `$PROFILE` (or shell rc on Linux/macOS):

```powershell
$env:TRUECOMMIT_COLOR = 'green'
```

### GitHub commits

`-GitHub` reads your GitHub contribution data for the last year, using your `gh` login or `$env:GITHUB_TOKEN`.
GitHub only reports how many commits you made per repo per day, so TrueCommit adds whatever GitHub has
beyond the pushed commits it already found locally for that repo and day. Nothing is counted twice.
In a single repo it only adds that repo's GitHub commits; in folder or `-All` mode it adds all of them.

GitHub itself only counts commits on a repo's default branch, made with an email linked to your account.
For private repos, "Include private contributions on my profile" may also need to be on.

Commits are matched by each repo's `user.email` (falling back to your global one), de-duplicated across
clones, and merge commits are skipped. "Unpushed" counts your commits that no remote-tracking branch contains.
