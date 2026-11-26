#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
game="${STARDEW_GAME_PATH:-$HOME/.local/share/Steam/steamapps/common/Stardew Valley}"
: "${STARDEW_TELEMETRY_TOKEN:?Export STARDEW_TELEMETRY_TOKEN first}"
test -f "$game/StardewModdingAPI.dll" || { echo "SMAPI not found: $game" >&2; exit 1; }
dotnet build -c Release -p:GamePath="$game"
destination="$game/Mods/OrinocoTelemetry"
mkdir -p "$destination"
cp bin/Release/net6.0/Orinoco.Stardew.dll manifest.json "$destination/"
umask 077
python3 - "$destination/config.json" <<'PY'
import json, os, sys
path = sys.argv[1]
data = {"Endpoint": "http://127.0.0.1:31050/stardew/telemetry", "Token": os.environ["STARDEW_TELEMETRY_TOKEN"]}
with open(path + ".tmp", "w") as f:
    json.dump(data, f, indent=2)
os.chmod(path + ".tmp", 0o600)
os.replace(path + ".tmp", path)
PY
echo "Installed $destination"
