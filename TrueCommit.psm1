# TrueCommit - GitHub-style heatmap of your *local* git commits (pushed or not), optionally merged with GitHub's.

$e = [char]27
$Colors = [ordered]@{ orange = '215;119;87'; green = '57;211;83'; blue = '88;166;255'; purple = '163;113;247'; pink = '219;97;162' }
$Dim = '110;110;110'; $Lilac = '177;185;249'
# -Lines ignores these paths: vendored folders, lockfiles, and data/asset formats that tools write, not people.
$NotCode = '(^|/)(vendor|third_party|node_modules|dist|build)/|\.(json|lock|obj|gltf|svg|csv|tsv|rbxmx|rbxlx|map|snap)}?$|\.min\.js$|(^|/)(yarn\.lock|pnpm-lock\.yaml|go\.sum)$'
$Dot = [char]0x00B7   # non-ASCII chars stay in code so Windows PowerShell 5.1 can read this file without a BOM
function Paint([string]$rgb, [string]$s, [switch]$Bold) {
    $b = if ($Bold) { "$e[1m" } else { '' }
    "$b$e[38;2;${rgb}m$s$e[0m"
}

function Find-GitRepo([string]$Root, [int]$Depth) {
    # Breadth-first; stop descending once a repo is found, skip hidden/heavy folders.
    $queue = [System.Collections.Generic.Queue[object]]::new()
    $queue.Enqueue(@($Root, 0))
    while ($queue.Count) {
        $dir, $d = $queue.Dequeue()
        if (Test-Path -LiteralPath (Join-Path $dir '.git')) { $dir; continue }
        if ($d -ge $Depth) { continue }
        Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch '^(\..*|node_modules|AppData|Library|\$Recycle\.Bin)$' -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
            ForEach-Object { $queue.Enqueue(@($_.FullName, ($d + 1))) }
    }
}

function Start-Git([string]$Repo, [string[]]$GitArgs) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new('git', ((@('-C', $Repo) + $GitArgs | ForEach-Object { "`"$_`"" }) -join ' '))
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $null = $p.StandardError.ReadToEndAsync()   # drain so a chatty error can't block the process
    $p
}

function Get-GitHubCommitDays([datetime]$From) {
    # One row per repo and day: @{ Slug = 'owner/name'; Date = 'yyyy-MM-dd'; Count = n }.
    # contributions(first:100) is capped, so ask in four ~93-day chunks: no repo can pass 100 days inside one.
    $now = [datetime]::UtcNow; $fmt = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    $chunks = for ($i = 0; $i -lt 4; $i++) {
        $a = $From.ToUniversalTime().AddDays(93 * $i); $b = $a.AddDays(93)
        if ($a -ge $now) { break }
        if ($b -gt $now) { $b = $now }
        "q${i}: contributionsCollection(from: `"$($a.ToString($fmt))`", to: `"$($b.ToString($fmt))`") { ...c }"
    }
    $query = "query { viewer { $($chunks -join ' ') } } fragment c on ContributionsCollection { commitContributionsByRepository(maxRepositories: 100) { repository { nameWithOwner } contributions(first: 100) { nodes { occurredAt commitCount } } } }"
    $body = @{ query = $query } | ConvertTo-Json -Compress
    # GITHUB_TOKEN first, else borrow the GitHub CLI's login (piping the query into gh garbles it on 5.1).
    $token = $env:GITHUB_TOKEN
    if (-not $token -and (Get-Command gh -ErrorAction SilentlyContinue)) { $token = gh auth token 2>$null; $global:LASTEXITCODE = 0 }
    $res = if ($token) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12   # 5.1 may default to TLS 1.0
        try { Invoke-RestMethod -Method Post -Uri 'https://api.github.com/graphql' -Headers @{ Authorization = "bearer $token" } -Body $body } catch { $null }
    }
    if (-not $res.data.viewer) { Write-Warning 'Could not read GitHub: run "gh auth login" or set $env:GITHUB_TOKEN. Showing local commits only.'; return }
    foreach ($chunk in $res.data.viewer.PSObject.Properties.Value) {
        foreach ($r in $chunk.commitContributionsByRepository) {
            foreach ($n in $r.contributions.nodes) {
                # PowerShell 7 turns ISO strings into dates, 5.1 doesn't. Days come stamped 07:00Z (US Pacific midnight), so the UTC date is the day.
                $day = if ($n.occurredAt -is [datetime]) { $n.occurredAt.ToUniversalTime().ToString('yyyy-MM-dd') } else { $n.occurredAt.Substring(0, 10) }
                @{ Slug = $r.repository.nameWithOwner.ToLower(); Name = $r.repository.nameWithOwner.Split('/')[1]; Date = $day; Count = [int]$n.commitCount }
            }
        }
    }
}

function Get-Streaks([string[]]$ActiveDays, [datetime]$Today) {
    $set = [System.Collections.Generic.HashSet[string]]::new([string[]]$ActiveDays)
    $longest = 0; $run = 0; $prev = $null
    foreach ($day in ($ActiveDays | Sort-Object)) {
        $dt = [datetime]$day
        $run = if ($prev -and ($dt - $prev).Days -eq 1) { $run + 1 } else { 1 }
        if ($run -gt $longest) { $longest = $run }
        $prev = $dt
    }
    # Current streak may end today or yesterday (today isn't over yet).
    $cur = 0; $d = $Today
    if (-not $set.Contains($d.ToString('yyyy-MM-dd'))) { $d = $d.AddDays(-1) }
    while ($set.Contains($d.ToString('yyyy-MM-dd'))) { $cur++; $d = $d.AddDays(-1) }
    $longest, $cur
}

function Show-TrueCommit {
    <#
    .SYNOPSIS
    Shows a GitHub-style contribution heatmap built from local git history, including unpushed commits.
    .EXAMPLE
    truecommit              # current repo (or every repo below the current folder)
    .EXAMPLE
    truecommit -All         # every repo under your user folder
    .EXAMPLE
    truecommit D:\code -Range 30d -Author me@example.com
    .EXAMPLE
    truecommit -All -GitHub -Color green   # add commits that are only on GitHub, in GitHub green
    .EXAMPLE
    truecommit -All -Lines  # lines of code changed instead of commits
    #>
    [CmdletBinding()]
    param(
        [string]$Path = '.',
        [switch]$All,
        [ValidateSet('all', '30d', '7d')][string]$Range = 'all',
        [string]$Author,
        [int]$Depth = 5,
        [string]$Color = $env:TRUECOMMIT_COLOR,
        [switch]$GitHub,
        [switch]$Lines
    )
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git was not found on PATH.' }
    if (-not $Color) { $Color = 'orange' }
    $Accent = if ($Colors[$Color]) { $Colors[$Color] }
        elseif ($Color -match '^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$') { ($Matches[1], $Matches[2], $Matches[3] | ForEach-Object { [Convert]::ToInt32($_, 16) }) -join ';' }
        else { throw "Unknown color '$Color'. Use $($Colors.Keys -join ', ') or a hex value like #39d353." }

    $root = if ($All) { if ($env:TRUECOMMIT_ROOT) { $env:TRUECOMMIT_ROOT } else { $HOME } } else { (Resolve-Path -LiteralPath $Path).Path }
    $top = if (-not $All) { git -C $root rev-parse --show-toplevel 2>$null }
    $repos = @(if ($top) { $top } else { Find-GitRepo $root $Depth })
    if (-not $repos) { Write-Host "No git repositories found under $root"; return }

    $globalEmail = git config --global user.email
    $global:LASTEXITCODE = 0   # "not a repo" / "no email" are expected answers, not failures for the caller
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $commits = [System.Collections.Generic.List[object]]::new()
    $unpushedSet = [System.Collections.Generic.HashSet[string]]::new()
    # Each git start costs ~0.3s on Windows, so launch every repo's queries at once, then collect.
    $jobs = foreach ($repo in $repos) {
        # Read .git/config directly instead of spawning git (worktrees have a .git file, not a folder).
        $cfg = "$repo/.git/config"
        $cfgText = if (Test-Path -LiteralPath $cfg -PathType Leaf) { Get-Content -LiteralPath $cfg -Raw } else { '' }
        $who = $Author
        if (-not $who) { $who = if ($cfgText -match '(?m)^\s*email\s*=\s*(\S+)') { $Matches[1] } else { $globalEmail } }
        $filter = @(if ($who) { "--author=$who" })
        # --numstat only with -Lines: diffing every commit is 3-15x slower than listing them.
        $stat = @(if ($Lines) { '--numstat' })
        [pscustomobject]@{
            Name  = Split-Path $repo -Leaf
            Slug  = $(if ($cfgText -match '(?m)^\s*url\s*=\s*\S*github\.com[:/]([^/\s]+/[^/\s]+?)(\.git)?/?\s*$') { $Matches[1].ToLower() })
            Log   = Start-Git $repo (@('log', '--all', '--no-merges', '--date=short', '--format=%H%x20%ad') + $stat + $filter)
            Ahead = Start-Git $repo (@('rev-list', '--no-merges', '--all', '--not', '--remotes') + $filter)
        }
    }
    $skipped = 0
    foreach ($j in $jobs) {
        foreach ($h in $j.Ahead.StandardOutput.ReadToEnd().Split("`n", [StringSplitOptions]::RemoveEmptyEntries)) { $null = $unpushedSet.Add($h.Trim()) }
        $c = $null
        foreach ($line in $j.Log.StandardOutput.ReadToEnd().Split("`n", [StringSplitOptions]::RemoveEmptyEntries)) {
            if ($line -match '^(\d+)\t(\d+)\t(.*)') {
                # One file of the current commit. Data/asset exports, vendored code and any file with 5000+ changed
                # lines aren't written by hand - in one Roblox repo .rbxlx saves alone were 1.8M "lines".
                if (-not $c) { continue }
                $add = [int]$Matches[1]; $del = [int]$Matches[2]
                if ($add + $del -gt 5000 -or $Matches[3] -match $NotCode) { $skipped++ } else { $c.Add += $add; $c.Del += $del }
                continue
            }
            if ($line -notmatch '^[0-9a-f]{40} ') { continue }   # binary files show as "-<tab>-<tab>path"
            $h, $date = $line.Trim().Split(' ')
            $c = if ($seen.Add($h)) { [pscustomobject]@{ Date = $date; Repo = $j.Name; Slug = $j.Slug; Pushed = -not $unpushedSet.Contains($h); Add = 0; Del = 0; Weight = 1 } }
            if ($c) { $commits.Add($c) }
        }
    }
    $unpushed = $unpushedSet.Count
    $repoCount = $repos.Count

    $today = (Get-Date).Date
    $start = $today.AddDays(-364); $start = $start.AddDays(-[int]$start.DayOfWeek)

    if ($GitHub -and $Lines) { Write-Warning 'GitHub only reports commit counts, not lines, so -GitHub adds nothing to -Lines.' }
    elseif ($GitHub) {
        # GitHub only reports commit counts per repo and day, so it can't be matched by hash. Per repo and day,
        # add only what GitHub has beyond the pushed commits found locally - that part was made on another machine.
        $local = @{}; $nameOf = @{}
        foreach ($j in $jobs) { if ($j.Slug) { $nameOf[$j.Slug] = $j.Name } }
        foreach ($c in $commits) { if ($c.Pushed -and $c.Slug) { $local["$($c.Slug)|$($c.Date)"] = 1 + [int]$local["$($c.Slug)|$($c.Date)"] } }
        $ghOnly = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($r in (Get-GitHubCommitDays $start)) {
            if ($top -and $r.Slug -ne $jobs[0].Slug) { continue }   # single-repo view: only that repo's GitHub side
            $name = if ($nameOf[$r.Slug]) { $nameOf[$r.Slug] } else { $null = $ghOnly.Add($r.Slug); $r.Name }
            for ($i = [int]$local["$($r.Slug)|$($r.Date)"]; $i -lt $r.Count; $i++) {
                $commits.Add([pscustomobject]@{ Date = $r.Date; Repo = $name; Slug = $r.Slug; Pushed = $true; Add = 0; Del = 0; Weight = 1 })
            }
        }
        $repoCount += $ghOnly.Count
    }

    # Everything below weighs a commit as 1, or with -Lines as its changed lines; a day of only binary changes stays empty.
    $unit = if ($Lines) { 'lines' } else { 'commits' }
    if ($Lines) { foreach ($c in $commits) { $c.Weight = $c.Add + $c.Del } }
    $byDay = @{}
    foreach ($c in $commits) { if ($c.Weight) { $byDay[$c.Date] = $c.Weight + [int]$byDay[$c.Date] } }

    # --- Heatmap: last 53 weeks, Sunday-first columns like GitHub ---
    $weeks = [int][math]::Floor(($today - $start).Days / 7) + 1
    $inWindow = @(for ($d = $start; $d -le $today; $d = $d.AddDays(1)) { [int]$byDay[$d.ToString('yyyy-MM-dd')] }) | Where-Object { $_ } | Sort-Object
    $q = if ($inWindow) { 1..3 | ForEach-Object { $inWindow[[math]::Floor($inWindow.Count * $_ / 4)] } } else { 1, 1, 1 }
    $shades = [char]0x2591, [char]0x2592, [char]0x2593, [char]0x2588

    $header = [char[]](' ' * ($weeks + 3)); $lastMonth = -1; $free = 0
    for ($w = 0; $w -lt $weeks; $w++) {
        $m = $start.AddDays($w * 7)
        if ($m.Month -ne $lastMonth -and $w -ge $free) {
            $m.ToString('MMM', [cultureinfo]::InvariantCulture).ToCharArray().CopyTo($header, $w); $free = $w + 4
        }
        $lastMonth = $m.Month
    }
    $out = @('', ('    ' + (-join $header).TrimEnd()))
    $labels = @{ 1 = 'Mon '; 3 = 'Wed '; 5 = 'Fri ' }
    # Paint once, index per cell: calling Paint 370 times costs ~1s on Windows PowerShell.
    $cell = @(Paint $Dim $Dot) + @(0..3 | ForEach-Object { Paint $Accent $shades[$_] })
    for ($row = 0; $row -lt 7; $row++) {
        $cells = for ($w = 0; $w -lt $weeks; $w++) {
            $d = $start.AddDays($w * 7 + $row)
            if ($d -gt $today) { ' '; continue }
            $n = [int]$byDay[$d.ToString('yyyy-MM-dd')]
            $cell[$(if (-not $n) { 0 } elseif ($n -gt $q[2]) { 4 } elseif ($n -gt $q[1]) { 3 } elseif ($n -gt $q[0]) { 2 } else { 1 })]
        }
        $label = if ($labels[$row]) { $labels[$row] } else { '    ' }
        $out += $label + (-join $cells)
    }
    $out += ''
    $out += '    Less ' + ((0..3 | ForEach-Object { Paint $Accent $shades[$_] }) -join ' ') + ' More'
    $out += ''

    # --- Range tabs ---
    $tabs = [ordered]@{ all = 'All time'; '7d' = 'Last 7 days'; '30d' = 'Last 30 days' }
    $out += ($tabs.Keys | ForEach-Object { if ($_ -eq $Range) { Paint $Accent $tabs[$_] -Bold } else { Paint $Dim $tabs[$_] } }) -join (Paint $Dim " $Dot ")
    $out += ''

    # --- Stats for the selected range ---
    $from = switch ($Range) { '7d' { $today.AddDays(-6) } '30d' { $today.AddDays(-29) } default { [datetime]::MinValue } }
    # Dates are yyyy-MM-dd strings, so plain string comparison orders them; hashtables beat Group-Object on 5.1.
    $fromS = $from.ToString('yyyy-MM-dd'); $todayS = $today.ToString('yyyy-MM-dd')
    $sel = $commits.Where({ $_.Date -ge $fromS -and $_.Date -le $todayS })
    if (-not $sel.Count) { $out += Paint $Dim 'No commits in this range.'; $out | Write-Host; return }

    $perRepo = @{}
    foreach ($c in $sel) { if ($c.Weight) { $perRepo[$c.Repo] = $c.Weight + [int]$perRepo[$c.Repo] } }
    $dayNames = @($byDay.Keys.Where({ $_ -ge $fromS -and $_ -le $todayS }) | Sort-Object)
    if (-not $dayNames) { $out += Paint $Dim "No $unit in this range."; $out | Write-Host; return }
    $total = ($perRepo.Values | Measure-Object -Sum).Sum
    $first = $dayNames[0]
    $span = if ($Range -eq 'all') { ($today - [datetime]$first).Days + 1 } else { ($today - $from).Days + 1 }
    $longest, $current = Get-Streaks $dayNames $today
    $topDay = $dayNames | Sort-Object { $byDay[$_] } -Descending | Select-Object -First 1
    $fav = $perRepo.Keys | Sort-Object { $perRepo[$_] } -Descending | Select-Object -First 1
    $activeRepos = $perRepo.Count

    $kv = { param($k, $v, $extra) @{ Plain = "${k}: $v$extra"; Ansi = "${k}: " + (Paint $Accent $v) + $(if ($extra) { Paint $Dim $extra }) } }
    $rows = @(
        @((& $kv 'Favorite repo' $fav), $(if ($Lines) {
            $add = ($sel | Measure-Object Add -Sum).Sum; $del = ($sel | Measure-Object Del -Sum).Sum
            @{ Plain = ('Lines: +{0:N0} -{1:N0}' -f $add, $del); Ansi = 'Lines: ' + (Paint $Accent ('+{0:N0}' -f $add)) + ' ' + (Paint $Dim ('-{0:N0}' -f $del)) }
        } else { & $kv 'Total commits' $sel.Count })),
        @(@{ Plain = ''; Ansi = '' }, @{ Plain = ''; Ansi = '' }),
        @((& $kv 'Repos' $activeRepos "/$repoCount"), (& $kv 'Unpushed' $unpushed)),
        @((& $kv 'Active days' $dayNames.Count "/$span"), (& $kv 'Longest streak' "$longest" ' days')),
        @((& $kv 'Most active day' ([datetime]$topDay).ToString('MMM d', [cultureinfo]::InvariantCulture)), (& $kv 'Current streak' "$current" ' days'))
    )
    $width = ($rows | ForEach-Object { $_[0].Plain.Length } | Measure-Object -Maximum).Maximum + 4
    foreach ($r in $rows) { $out += $r[0].Ansi + (' ' * ($width - $r[0].Plain.Length)) + $r[1].Ansi }
    $out += Paint $Dim ("First commit {0} {4} Busiest day {1:N0} {3} {4} {2:N1} {3} per active day" -f
        ([datetime]$first).ToString('MMM d, yyyy', [cultureinfo]::InvariantCulture), $byDay[$topDay], ($total / $dayNames.Count), $unit, $Dot)
    if ($skipped) { $out += Paint $Dim "Not counted (all time): $skipped changes to generated, vendored or data files" }
    $out += ''
    $out += Paint $Lilac $(if ($unpushed) { "$unpushed of your commits exist only on this machine - GitHub has never seen them" } else { 'Everything is pushed. GitHub knows it all.' })
    $out | Write-Host
}

Set-Alias truecommit Show-TrueCommit
Export-ModuleMember -Function Show-TrueCommit -Alias truecommit
