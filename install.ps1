# Installs TrueCommit into your user module folder, from this clone or straight from GitHub:
#   irm https://raw.githubusercontent.com/nyad-dev/TrueCommit/main/install.ps1 | iex
$source = 'https://raw.githubusercontent.com/nyad-dev/TrueCommit/main'
$dest = Join-Path ($env:PSModulePath -split [IO.Path]::PathSeparator)[0] 'TrueCommit'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
foreach ($f in 'TrueCommit.psm1', 'TrueCommit.psd1') {
    if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot $f))) { Copy-Item (Join-Path $PSScriptRoot $f) $dest -Force }
    else { Invoke-WebRequest "$source/$f" -OutFile (Join-Path $dest $f) -UseBasicParsing }
}
Write-Host "TrueCommit installed to $dest - open a new terminal and run: truecommit"
