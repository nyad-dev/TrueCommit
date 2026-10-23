@{
RootModule = 'TrueCommit.psm1'
ModuleVersion = '0.1.0'
GUID = 'dfef7391-7fec-4de7-8e4a-b3e440591db0'
Author = 'nyad-dev'
CompanyName = 'Unknown'
Copyright = '(c) 2026 nyad-dev. Alle Rechte vorbehalten.'
Description = 'GitHub-style contribution heatmap of your local git commits, including the ones you never pushed.'
PowerShellVersion = '5.1'
FunctionsToExport = 'Show-TrueCommit'
CmdletsToExport = @()
AliasesToExport = 'truecommit'
PrivateData = @{
    PSData = @{
        Tags = 'git', 'heatmap', 'commits', 'contributions', 'terminal'
        ProjectUri = 'https://github.com/nyad-dev/TrueCommit'
    } # Ende der PSData-Hashtabelle
} # Ende der PrivateData-Hashtabelle
}
