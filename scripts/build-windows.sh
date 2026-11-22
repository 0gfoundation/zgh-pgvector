#!/usr/bin/env bash
# Build pgvector with MSVC against EDB's Postgres Windows binaries, the zip zonky
# repackages as its windows-amd64 bundle, so headers and postgres.lib match the
# postgres.exe vector.dll loads into.
# Usage: build-windows.sh <pgvector_version> <zonky_version> <stage_dir> <edb_dir>
# Runs in Git Bash on a GitHub Windows runner. EDB's Postgres lands in <edb_dir>/pgsql
# (its bin has the psql the smoke uses; zonky's bundle has none).
set -euo pipefail
ver=$1 zver=$2 stage=$3 edb=$4
here=$(cd "$(dirname "$0")" && pwd)

work=$(mktemp -d)
cd "$work"

# zonky 18.6.0 repackages postgresql-18.6-1-windows-x64-binaries.zip.
edb_ver=${zver%.0}-1
case "$zver" in *.0) ;; *) echo "unexpected zonky version $zver" >&2; exit 1 ;; esac
# EDB publishes no checksums, and the cmp below covers only postgres.exe, not the
# headers compiled into vector.dll: pin each zip. A new version needs its hash added.
case "$edb_ver" in
  18.6-1) edb_sha256=fbe23da234ee31547bf8a36d29dfd81e82b849df2d2b78d2eecb43d360252f8c ;;
  *) echo "no pinned sha256 for EDB $edb_ver; add one to $0" >&2; exit 1 ;;
esac
curl -fsSL --retry 5 -o edb.zip "https://get.enterprisedb.com/postgresql/postgresql-$edb_ver-windows-x64-binaries.zip"
echo "$edb_sha256  edb.zip" | sha256sum -c
rm -rf "$edb"; mkdir -p "$edb"
# Windows' own bsdtar, not Git Bash's unzip: that one's 'pgsql/include/*' skipped include/server.
"$SYSTEMROOT/System32/tar.exe" -xf edb.zip -C "$edb" pgsql/bin pgsql/include pgsql/lib
rm edb.zip
pgroot=$(cd "$edb/pgsql" && pwd)

# Same build as zonky's: its postgres.exe must be byte-identical to EDB's.
base=https://repo1.maven.org/maven2/io/zonky/test/postgres/embedded-postgres-binaries-windows-amd64/$zver
jar=embedded-postgres-binaries-windows-amd64-$zver.jar
curl -fsSL --retry 5 -o zonky.jar "$base/$jar"
curl -fsSL --retry 5 -o zonky.jar.sha256 "$base/$jar.sha256"
echo "$(tr -d ' \n' < zonky.jar.sha256)  zonky.jar" | sha256sum -c
mkdir zjar zpg
unzip -q zonky.jar -d zjar
tar -xJf zjar/*.txz -C zpg bin/postgres.exe
sha256sum zpg/bin/postgres.exe "$pgroot/bin/postgres.exe"
cmp zpg/bin/postgres.exe "$pgroot/bin/postgres.exe" \
  || { echo "EDB $edb_ver postgres.exe differs from zonky $zver's" >&2; exit 1; }
for f in include/server/postgres.h include/server/port/win32_msvc lib/postgres.lib; do
  [ -e "$pgroot/$f" ] || { echo "EDB zip has no $f" >&2; exit 1; }
done

src=$work/pgvector
git clone -q --depth 1 --branch "v$ver" https://github.com/pgvector/pgvector "$src"
# Makefile.win's OPTFLAGS is empty by default (no /arch), so the DLL runs on any x64 CPU.
cmd //c "$(cygpath -w "$here/nmake-msvc.cmd")" "$(cygpath -w "$src")" "$(cygpath -w "$pgroot")"

dll=$src/vector.dll
# Every DLL vector.dll imports must be postgres.exe or one zonky's postgres.exe imports itself.
deps() { tr -d '\r' < "$1" | awk '/Image has the following dependencies/ {on=1; next} on && /^ *$/ && n {exit} on && NF {print tolower($1); n++}' | sort -u; }
echo "--- vector.dll imports"; deps "$src/vector.deps"
deps "$src/vector.deps" | grep -qx postgres.exe || { echo "no postgres.exe among vector.dll's imports: dumpbin output not parsed" >&2; exit 1; }
bad=$(comm -23 <(deps "$src/vector.deps") <( (deps "$src/postgres.deps"; echo postgres.exe) | sort -u))
if [ -n "$bad" ]; then echo "vector.dll imports DLLs postgres.exe does not: $bad" >&2; exit 1; fi

"$here/stage.sh" "$src" "$dll" "$stage"
