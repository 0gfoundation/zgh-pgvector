# zgh-pgvector

[pgvector](https://github.com/pgvector/pgvector) builds for
[zgh](https://github.com/0gfoundation/zgh)'s embedded Postgres.

zgh can start a local Postgres from
[zonky's embedded-postgres-binaries](https://github.com/zonkyio/embedded-postgres-binaries)
bundles. Those bundles carry no pgvector, so this repo builds it and
publishes one tarball per zonky target as a GitHub release. zgh pins each
asset's sha256.

## Targets

Named as zonky names them:

| Target           | Built on                                   |
| ---------------- | ------------------------------------------ |
| `darwin-arm64v8` | `macos-15`, Homebrew `postgresql@18`       |
| `darwin-amd64`   | `macos-15-intel`, Homebrew `postgresql@18` |
| `linux-amd64`    | `debian:bookworm` on `ubuntu-latest`, PGDG `postgresql-server-dev-18` |
| `linux-arm64v8`  | `debian:bookworm` on `ubuntu-24.04-arm`, PGDG `postgresql-server-dev-18` |
| `windows-amd64`  | `windows-latest`, MSVC `nmake /F Makefile.win` against EDB's `postgresql-18.6-1-windows-x64-binaries.zip` |

All builds pass `OPTFLAGS=""`, so they skip pgvector's default
`-march=native` and run on any CPU of the arch. macOS builds set
`MACOSX_DEPLOYMENT_TARGET=11.0`, and the build fails if `otool -L` lists
a library outside `/usr/lib` and `/System`. Linux builds fail if `ldd`
resolves a library outside `/lib` and `/usr/lib`.

zonky's windows-amd64 bundle is EDB's Windows binaries zip, repackaged
without `include/` or `postgres.lib`. The Windows build takes those from the
same EDB zip, pinned by sha256 in `scripts/build-windows.sh` (EDB publishes
none), and fails unless its `postgres.exe` is byte-identical to the zonky
bundle's. pgvector's `Makefile.win` sets no `/arch`, so the DLL runs
on any x64 CPU, and passes no `/MD`, so the C runtime is linked statically.
The build fails if `vector.dll` imports a DLL other than `postgres.exe` and
the ones zonky's `postgres.exe` imports itself; 0.8.7's imports are
`postgres.exe` and `KERNEL32.dll`.

## Release assets

Release `pgvector-<ver>-pg<major>` holds `SHA256SUMS` and, per target,
`pgvector-<ver>-pg<major>-<target>.tar.gz`, which unpacks to:

```
LICENSE
lib/postgresql/vector.dylib   (macOS) or vector.so (Linux)
share/postgresql/extension/vector.control
share/postgresql/extension/vector--*.sql
```

or, for `windows-amd64`, whose zonky bundle has no `postgresql/` level:

```
LICENSE
lib/vector.dll
share/extension/vector.control
share/extension/vector--*.sql
```

The paths match zonky's bundle layout: unpack a tarball over an unpacked
bundle and `CREATE EXTENSION vector` works.

## Smoke test

Before publishing, each target's job downloads the zonky bundle
`io.zonky.test.postgres:embedded-postgres-binaries-<target>` from Maven
Central, checks it against Maven's `.sha256`, copies the tarball in,
runs `initdb`, starts Postgres on a Unix socket (Windows: TCP on
127.0.0.1, with EDB's `psql`, since zonky ships none), and checks:

- `CREATE EXTENSION vector`;
- `SELECT '[1,2,3]'::vector <-> '[2,3,5]'` returns `2.449489742783178`;
- with an HNSW index (`vector_cosine_ops`) and `enable_seqscan = off`,
  the nearest row to `[0.9,0.1,0]` among `[1,0,0]` and `[0,1,0]` is
  `[1,0,0]`, and the plan uses the index.

On Linux it also fails if `vector.so` needs a newer glibc than zonky's
own `postgres` binary. The release job runs only when all five pass.

## Re-running the build

Actions → **build** → Run workflow, or:

```sh
gh workflow run build.yml -R 0gfoundation/zgh-pgvector \
  -f pgvector_version=0.8.7 -f pg_major=18 -f zonky_version=18.6.0
```

Only a run from `main` publishes; a run from another branch
(`--ref <branch>`) builds and smoke-tests. The release job fails if the
tag already exists: published assets never
change, because zgh pins their hashes. For a new pgvector or Postgres
version, run it with new inputs, then update the pins in zgh.

## License

`LICENSE` is pgvector's license (the PostgreSQL License). Every tarball
ships it.
