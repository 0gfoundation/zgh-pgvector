#!/usr/bin/env bash
# Publish the tarballs in the current dir as GitHub release <tag>.
# A new tag gets every tarball plus SHA256SUMS. An existing tag gets only the
# tarballs it lacks, each with its own SHA256SUMS-<target>. The assets it already
# has are never re-uploaded or deleted, and the script fails if any of their
# digests changed.
# Usage: release.sh <tag> <tarball_count> <notes>
# Needs GH_TOKEN, GITHUB_REPOSITORY, GITHUB_SHA, GITHUB_SERVER_URL and GITHUB_RUN_ID.
set -euo pipefail
tag=$1 count=$2 notes=$3
repo=$GITHUB_REPOSITORY

test "$(ls *.tar.gz | wc -l)" -eq "$count"
sha256sum *.tar.gz | tee all.sha256

if ! gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  cp all.sha256 SHA256SUMS
  gh release create "$tag" *.tar.gz SHA256SUMS \
    --repo "$repo" --target "$GITHUB_SHA" --title "$tag" --notes "$notes"
  exit 0
fi

assets() { gh release view "$tag" --repo "$repo" --json assets --jq '.assets[] | "\(.name) \(.digest)"' | LC_ALL=C sort; }
before=$(assets)
echo "--- $tag already has"; echo "$before"

up=()
for f in *.tar.gz; do
  grep -qF "$f " <<<"$before" && continue
  t=${f#"$tag"-}; t=${t%.tar.gz}
  sums=SHA256SUMS-$t
  if grep -qF "$sums " <<<"$before"; then echo "$tag has $sums but not $f" >&2; exit 1; fi
  grep -F "  $f" all.sha256 > "$sums"
  up+=("$f" "$sums")
done
[ ${#up[@]} -gt 0 ] || { echo "$tag already has every tarball: nothing to upload" >&2; exit 1; }

# No --clobber: an asset name that exists makes the upload fail, never replaces it.
gh release upload "$tag" "${up[@]}" --repo "$repo"
gh release view "$tag" --repo "$repo" --json body --jq .body > notes.md
printf '\n\nAdded %s, built by run %s/%s/actions/runs/%s.\n' "${up[*]}" "$GITHUB_SERVER_URL" "$repo" "$GITHUB_RUN_ID" >> notes.md
gh release edit "$tag" --repo "$repo" --notes-file notes.md

after=$(assets)
echo "--- $tag now has"; echo "$after"
changed=$(LC_ALL=C comm -23 <(echo "$before") <(echo "$after"))
[ -z "$changed" ] || { echo "assets that were on $tag changed or went missing: $changed" >&2; exit 1; }
for f in "${up[@]}"; do
  grep -qxF "$f sha256:$(sha256sum "$f" | cut -d' ' -f1)" <<<"$after" \
    || { echo "uploaded $f's digest does not match the local file" >&2; exit 1; }
done
