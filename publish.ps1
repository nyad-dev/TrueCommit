# Publishes only the module files (not .git/CI) to the PowerShell Gallery. Bump ModuleVersion in TrueCommit.psd1 first.
#   ./publish.ps1 -ApiKey <key from powershellgallery.com>
# Needs PSResourceGet; Windows PowerShell's built-in PowerShellGet 1.0 can't publish anymore:
#   Install-Module Microsoft.PowerShell.PSResourceGet -Scope CurrentUser
param([string]$ApiKey, [string]$Repository = 'PSGallery')
$ErrorActionPreference = 'Stop'
$key = @{}; if ($ApiKey) { $key.ApiKey = $ApiKey }   # a local test repository takes no key
$stage = Join-Path ([IO.Path]::GetTempPath()) 'TrueCommit'
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $stage | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'TrueCommit.psm1'), (Join-Path $PSScriptRoot 'TrueCommit.psd1') $stage
Publish-PSResource -Path $stage -Repository $Repository @key
Write-Host "Published TrueCommit to $Repository"
