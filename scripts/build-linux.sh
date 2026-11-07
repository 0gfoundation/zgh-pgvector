#!/usr/bin/env bash
# Build pgvector inside debian:bookworm against PGDG postgresql-server-dev-<major>.
# Usage: build-linux.sh <pgvector_version> <pg_major> <stage_dir>
set -euo pipefail
ver=$1 major=$2 stage=$3

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl gnupg git build-essential >/dev/null
install -d /usr/share/postgresql-common/pgdg
curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
  https://www.postgresql.org/media/keys/ACCC4CF8.asc
echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list
apt-get update -qq
apt-get install -y -qq --no-install-recommends "postgresql-server-dev-$major" >/dev/null

pg_config=/usr/lib/postgresql/$major/bin/pg_config
"$pg_config" --version

src=$(mktemp -d)
git clone -q --depth 1 --branch "v$ver" https://github.com/pgvector/pgvector "$src"
# OPTFLAGS="" drops pgvector's default -march=native, so the binary runs on any CPU of the arch.
make -C "$src" PG_CONFIG="$pg_config" OPTFLAGS=""

so=$src/vector.so
echo "--- ldd vector.so"
ldd "$so"
# Every resolved library must be a system one; no /nix/store, /usr/local or build paths.
bad=$(ldd "$so" | awk '/=>/ {print $3}' | grep -vE '^/(usr/)?lib/' || true)
if [ -n "$bad" ]; then echo "unexpected library paths: $bad" >&2; exit 1; fi

"$(dirname "$0")/stage.sh" "$src" "$so" "$stage"
