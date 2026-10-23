#!/bin/sh
# Installs TrueCommit on Linux/macOS (needs PowerShell 7) and adds a `truecommit` command for bash/zsh:
#   curl -fsSL https://raw.githubusercontent.com/nyad-dev/TrueCommit/main/install.sh | sh
set -e
command -v pwsh >/dev/null || { echo "TrueCommit needs PowerShell 7 (pwsh): https://aka.ms/install-powershell" >&2; exit 1; }
src=https://raw.githubusercontent.com/nyad-dev/TrueCommit/main
mod="${XDG_DATA_HOME:-$HOME/.local/share}/powershell/Modules/TrueCommit"
bin="$HOME/.local/bin"
here=$(dirname "$0")
mkdir -p "$mod" "$bin"
for f in TrueCommit.psm1 TrueCommit.psd1; do
  if [ -f "$here/$f" ]; then cp "$here/$f" "$mod/"; else curl -fsSL "$src/$f" -o "$mod/$f"; fi
done
printf '#!/usr/bin/env pwsh\nShow-TrueCommit @args\n' > "$bin/truecommit"
chmod +x "$bin/truecommit"
echo "TrueCommit installed. Run: truecommit"
case ":$PATH:" in *":$bin:"*) ;; *) echo "Add $bin to your PATH first." ;; esac
