#!/usr/bin/env bash
# Load a pgvector tarball into zonky's embedded Postgres bundle and query it.
# Usage: smoke.sh <zonky_target> <zonky_version> <tarball>
# Needs psql on PATH (any recent client).
set -euo pipefail
target=$1 zver=$2 tarball=$(cd "$(dirname "$3")" && pwd)/$(basename "$3")

# Short dir: macOS caps a socket path at 103 bytes, and $TMPDIR there is long.
work=$(mktemp -d /tmp/pgv.XXXXXX)
cd "$work"

base=https://repo1.maven.org/maven2/io/zonky/test/postgres/embedded-postgres-binaries-$target/$zver
jar=embedded-postgres-binaries-$target-$zver.jar
curl -fsSL --retry 5 -o zonky.jar "$base/$jar"
curl -fsSL --retry 5 -o zonky.jar.sha256 "$base/$jar.sha256"
# Git Bash on Windows has no shasum; macOS's BSD sha256sum reads no check list from stdin.
sha256() { if command -v shasum >/dev/null; then shasum -a 256 "$@"; else sha256sum "$@"; fi; }
echo "$(tr -d ' \n' < zonky.jar.sha256)  zonky.jar" | sha256 -c

mkdir jar pg ext
unzip -q zonky.jar -d jar
tar -xJf jar/*.txz -C pg
tar -xzf "$tarball" -C ext
cp -R ext/lib ext/share pg/

echo "--- zonky postgres binary"
case "$target" in
  windows-*) file pg/bin/postgres.exe ;;
  *) file pg/bin/postgres ;;
esac
case "$target" in
  linux-*)
    # vector.so must not need a newer glibc than zonky's own postgres does.
    maxver() { objdump -T "$1" | grep -oE 'GLIBC_[0-9.]+' | sed 's/GLIBC_//' | sort -V | tail -1; }
    pgv=$(maxver pg/bin/postgres); vv=$(maxver pg/lib/postgresql/vector.so)
    echo "max GLIBC: postgres $pgv, vector.so $vv"
    [ "$(printf '%s\n%s\n' "$pgv" "$vv" | sort -V | tail -1)" = "$pgv" ] \
      || { echo "vector.so needs GLIBC_$vv > postgres's GLIBC_$pgv" >&2; exit 1; } ;;
esac

pg/bin/initdb -D data -U zgh -A trust -E UTF8 --locale=C >/dev/null
case "$target" in
  windows-*)
    # TCP on loopback, on a port the OS picks: no Unix socket for psql on Windows.
    # The port is free when picked, not when Postgres binds it: one retry on a new port.
    for try in 1 2; do
      port=$(python -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
      conn=(-h 127.0.0.1 -p "$port")
      pg/bin/pg_ctl -D data -l pg.log -w -o "-c listen_addresses=127.0.0.1 -p $port" start && break
      cat pg.log
      [ "$try" = 2 ] && exit 1
    done ;;
  *)
    mkdir s
    conn=(-h "$work/s")
    pg/bin/pg_ctl -D data -l pg.log -w -o "-c listen_addresses='' -k $work/s" start \
      || { cat pg.log; exit 1; } ;;
esac
trap 'pg/bin/pg_ctl -D "$work/data" -m fast stop >/dev/null || true' EXIT

# tr: a Windows psql ends lines with CRLF.
psqlz() { psql "${conn[@]}" -U zgh -d postgres -XAtq -v ON_ERROR_STOP=1 "$@" | tr -d '\r'; }
q() { psqlz -c "$1"; }

q 'CREATE EXTENSION vector;'
echo "extension version: $(q "SELECT extversion FROM pg_extension WHERE extname = 'vector';")"

d=$(q "SELECT '[1,2,3]'::vector <-> '[2,3,5]';")
echo "distance: $d"
[ "$d" = "2.449489742783178" ] || { echo "unexpected distance $d" >&2; exit 1; }

q 'CREATE TABLE items (id int PRIMARY KEY, embedding vector(3));'
q "INSERT INTO items VALUES (1, '[1,0,0]'), (2, '[0,1,0]');"
q 'CREATE INDEX ON items USING hnsw (embedding vector_cosine_ops);'
plan=$(psqlz <<'SQL'
SET enable_seqscan = off;
EXPLAIN SELECT embedding FROM items ORDER BY embedding <=> '[0.9,0.1,0]' LIMIT 1;
SQL
)
echo "$plan"
echo "$plan" | grep -q 'items_embedding_idx' || { echo "HNSW index not used" >&2; exit 1; }
near=$(psqlz <<'SQL'
SET enable_seqscan = off;
SELECT embedding FROM items ORDER BY embedding <=> '[0.9,0.1,0]' LIMIT 1;
SQL
)
echo "nearest: $near"
[ "$near" = "[1,0,0]" ] || { echo "unexpected nearest $near" >&2; exit 1; }
echo "smoke ok: $target"
