# TrueCommit - GitHub-style heatmap of your *local* git commits (pushed or not).

$e = [char]27
$Orange = '215;119;87'; $Dim = '110;110;110'; $Lilac = '177;185;249'
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
    #>
    [CmdletBinding()]
    param(
        [string]$Path = '.',
        [switch]$All,
        [ValidateSet('all', '30d', '7d')][string]$Range = 'all',
        [string]$Author,
        [int]$Depth = 5
    )
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git was not found on PATH.' }

    $root = if ($All) { if ($env:TRUECOMMIT_ROOT) { $env:TRUECOMMIT_ROOT } else { $HOME } } else { (Resolve-Path -LiteralPath $Path).Path }
    $top = if (-not $All) { git -C $root rev-parse --show-toplevel 2>$null }
    $repos = @(if ($top) { $top } else { Find-GitRepo $root $Depth })
    if (-not $repos) { Write-Host "No git repositories found under $root"; return }

    $globalEmail = git config --global user.email
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $commits = [System.Collections.Generic.List[object]]::new()
    $unpushed = 0
    # Each git start costs ~0.3s on Windows, so launch every repo's queries at once, then collect.
    $jobs = foreach ($repo in $repos) {
        $who = $Author
        if (-not $who) {
            # Repo-local email from .git/config without spawning git (worktrees have a .git file, not a folder).
            $cfg = "$repo/.git/config"
            $local = if (Test-Path -LiteralPath $cfg -PathType Leaf) { Select-String -LiteralPath $cfg -Pattern '^\s*email\s*=\s*(\S+)' | Select-Object -First 1 }
            $who = if ($local) { $local.Matches[0].Groups[1].Value } else { $globalEmail }
        }
        $filter = @(if ($who) { "--author=$who" })
        # No --shortstat: diffing big binary assets made it ~15x slower.
        [pscustomobject]@{
            Name = Split-Path $repo -Leaf
            Log  = Start-Git $repo (@('log', '--all', '--no-merges', '--date=short', '--format=%H%x20%ad') + $filter)
            Ahead = Start-Git $repo (@('rev-list', '--count', '--no-merges', '--all', '--not', '--remotes') + $filter)
        }
    }
    foreach ($j in $jobs) {
        foreach ($line in $j.Log.StandardOutput.ReadToEnd().Split("`n", [StringSplitOptions]::RemoveEmptyEntries)) {
            $h, $date = $line.Trim().Split(' ')
            if ($seen.Add($h)) { $commits.Add([pscustomobject]@{ Date = $date; Repo = $j.Name }) }
        }
        $n = $j.Ahead.StandardOutput.ReadToEnd().Trim()
        if ($n) { $unpushed += [int]$n }
    }

    $today = (Get-Date).Date
    $byDay = @{}
    foreach ($c in $commits) { $byDay[$c.Date] = 1 + [int]$byDay[$c.Date] }

    # --- Heatmap: last 53 weeks, Sunday-first columns like GitHub ---
    $start = $today.AddDays(-364); $start = $start.AddDays(-[int]$start.DayOfWeek)
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
    $cell = @(Paint $Dim $Dot) + @(0..3 | ForEach-Object { Paint $Orange $shades[$_] })
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
    $out += '    Less ' + ((0..3 | ForEach-Object { Paint $Orange $shades[$_] }) -join ' ') + ' More'
    $out += ''

    # --- Range tabs ---
    $tabs = [ordered]@{ all = 'All time'; '7d' = 'Last 7 days'; '30d' = 'Last 30 days' }
    $out += ($tabs.Keys | ForEach-Object { if ($_ -eq $Range) { Paint $Orange $tabs[$_] -Bold } else { Paint $Dim $tabs[$_] } }) -join (Paint $Dim " $Dot ")
    $out += ''

    # --- Stats for the selected range ---
    $from = switch ($Range) { '7d' { $today.AddDays(-6) } '30d' { $today.AddDays(-29) } default { [datetime]::MinValue } }
    # Dates are yyyy-MM-dd strings, so plain string comparison orders them; hashtables beat Group-Object on 5.1.
    $fromS = $from.ToString('yyyy-MM-dd'); $todayS = $today.ToString('yyyy-MM-dd')
    $sel = $commits.Where({ $_.Date -ge $fromS -and $_.Date -le $todayS })
    if (-not $sel.Count) { $out += Paint $Dim 'No commits in this range.'; $out | Write-Host; return }

    $perRepo = @{}
    foreach ($c in $sel) { $perRepo[$c.Repo] = 1 + [int]$perRepo[$c.Repo] }
    $dayNames = @($byDay.Keys.Where({ $_ -ge $fromS -and $_ -le $todayS }) | Sort-Object)
    $first = $dayNames[0]
    $span = if ($Range -eq 'all') { ($today - [datetime]$first).Days + 1 } else { ($today - $from).Days + 1 }
    $longest, $current = Get-Streaks $dayNames $today
    $topDay = $dayNames | Sort-Object { $byDay[$_] } -Descending | Select-Object -First 1
    $fav = $perRepo.Keys | Sort-Object { $perRepo[$_] } -Descending | Select-Object -First 1
    $activeRepos = $perRepo.Count

    $kv = { param($k, $v, $extra) @{ Plain = "${k}: $v$extra"; Ansi = "${k}: " + (Paint $Orange $v) + $(if ($extra) { Paint $Dim $extra }) } }
    $rows = @(
        @((& $kv 'Favorite repo' $fav), (& $kv 'Total commits' $sel.Count)),
        @(@{ Plain = ''; Ansi = '' }, @{ Plain = ''; Ansi = '' }),
        @((& $kv 'Repos' $activeRepos "/$($repos.Count)"), (& $kv 'Unpushed' $unpushed)),
        @((& $kv 'Active days' $dayNames.Count "/$span"), (& $kv 'Longest streak' "$longest" ' days')),
        @((& $kv 'Most active day' ([datetime]$topDay).ToString('MMM d', [cultureinfo]::InvariantCulture)), (& $kv 'Current streak' "$current" ' days'))
    )
    $width = ($rows | ForEach-Object { $_[0].Plain.Length } | Measure-Object -Maximum).Maximum + 4
    foreach ($r in $rows) { $out += $r[0].Ansi + (' ' * ($width - $r[0].Plain.Length)) + $r[1].Ansi }
    $out += Paint $Dim ("First commit {0} {3} Busiest day {1} commits {3} {2:N1} commits per active day" -f
        ([datetime]$first).ToString('MMM d, yyyy', [cultureinfo]::InvariantCulture), $byDay[$topDay], ($sel.Count / $dayNames.Count), $Dot)
    $out += ''
    $out += Paint $Lilac $(if ($unpushed) { "$unpushed of your commits exist only on this machine - GitHub has never seen them" } else { 'Everything is pushed. GitHub knows it all.' })
    $out | Write-Host
}

Set-Alias truecommit Show-TrueCommit
Export-ModuleMember -Function Show-TrueCommit -Alias truecommit
