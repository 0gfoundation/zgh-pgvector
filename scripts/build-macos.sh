#!/usr/bin/env bash
# Build pgvector on macOS against Homebrew postgresql@<major>.
# Usage: build-macos.sh <pgvector_version> <pg_major> <stage_dir>
set -euo pipefail
ver=$1 major=$2 stage=$3

brew install --quiet "postgresql@$major"
pg_config=$(brew --prefix "postgresql@$major")/bin/pg_config
"$pg_config" --version

# Loads on macOS 11 and later (the brief needs 14+).
export MACOSX_DEPLOYMENT_TARGET=11.0

src=$(mktemp -d)
git clone -q --depth 1 --branch "v$ver" https://github.com/pgvector/pgvector "$src"
# OPTFLAGS="" drops -march=native; PG_SYSROOT points at this runner's SDK, not the bottle builder's.
make -C "$src" PG_CONFIG="$pg_config" OPTFLAGS="" PG_SYSROOT="$(xcrun --show-sdk-path)"

so=$src/vector.dylib
echo "--- otool -L vector.dylib"
otool -L "$so"
# Only system libraries: anything outside /usr/lib and /System would not exist on a user's Mac.
bad=$(otool -L "$so" | tail -n +2 | awk '{print $1}' | grep -vE '^/(usr/lib|System)/' || true)
if [ -n "$bad" ]; then echo "non-system libraries: $bad" >&2; exit 1; fi
echo "--- minos"
otool -l "$so" | grep -A4 LC_BUILD_VERSION | grep -E 'minos|platform'

"$(dirname "$0")/stage.sh" "$src" "$so" "$stage"
