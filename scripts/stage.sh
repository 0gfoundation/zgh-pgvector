#!/usr/bin/env bash
# Lay out the tarball contents in the zonky bundle's layout, plus LICENSE:
# lib/postgresql/<module> and share/postgresql/extension/vector.* (macOS, Linux),
# lib/vector.dll and share/extension/vector.* (Windows).
# Usage: stage.sh <pgvector_src> <module_file> <stage_dir>
set -euo pipefail
src=$1 so=$2 stage=$3
case "$so" in
  *.dll) lib=lib ext=share/extension ;;
  *) lib=lib/postgresql ext=share/postgresql/extension ;;
esac
rm -rf "$stage"
mkdir -p "$stage/$lib" "$stage/$ext"
cp "$so" "$stage/$lib/"
cp "$src/vector.control" "$src"/sql/vector--*.sql "$stage/$ext/"
cp "$src/LICENSE" "$stage/LICENSE"
find "$stage" -type f | sort
