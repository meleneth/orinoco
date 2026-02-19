#!/usr/bin/env bash
set -euo pipefail

# Root directory
ROOT="data"

# Create directory tree
mkdir -p \
  "$ROOT/development/goaws" \
  "$ROOT/production/goaws" \
  "$ROOT/production/orinoco-db" \
  "$ROOT/production/orinoco-db-cable" \
  "$ROOT/production/orinoco-db-cache" \
  "$ROOT/production/orinoco-db-queue" \
  "$ROOT/test/goaws" \
  "$ROOT/test/orinoco-db"

echo "Directory tree created under: $ROOT"
