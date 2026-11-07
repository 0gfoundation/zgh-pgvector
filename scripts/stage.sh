#!/usr/bin/env bash
# Lay out the tarball contents: lib/postgresql/<module>, share/postgresql/extension/vector.*, LICENSE.
# Usage: stage.sh <pgvector_src> <module_file> <stage_dir>
set -euo pipefail
src=$1 so=$2 stage=$3
rm -rf "$stage"
mkdir -p "$stage/lib/postgresql" "$stage/share/postgresql/extension"
cp "$so" "$stage/lib/postgresql/"
cp "$src/vector.control" "$src"/sql/vector--*.sql "$stage/share/postgresql/extension/"
cp "$src/LICENSE" "$stage/LICENSE"
find "$stage" -type f | sort
