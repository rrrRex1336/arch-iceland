#!/usr/bin/env bash
# Download the rootfs/boot artifacts of an arch-iceland Actions run with aria2.
#
#   RUN_ID=43566421101 DESKTOP=denial ./scripts/download-artifacts.sh [DEST]
#
# Without RUN_ID the latest successful run is used. The artifact URLs returned by
# the GitHub API are short-lived signed links, so they are resolved on every run.
set -euo pipefail

repo=${REPO:-rrrRex1336/arch-iceland}
desktop=${DESKTOP:-denial}
dest=${1:-${DEST:-images}}
run_id=${RUN_ID:-}

for c in gh aria2c unzip curl; do
	command -v "$c" >/dev/null || { echo "missing: $c" >&2; exit 1; }
done

if [ -z "$run_id" ]; then
	run_id=$(gh run list -R "$repo" --status success --limit 20 \
		--json databaseId,displayTitle,createdAt \
		-q '.[] | select(.displayTitle == "Build Arch Linux") | .databaseId' | head -1)
	[ -n "$run_id" ] || { echo "no successful run found" >&2; exit 1; }
fi
echo "run: $run_id (desktop: $desktop)"

mkdir -p "$dest"
cd "$dest"

token=$(gh auth token)
for kind in rootfs boot; do
	name="arch-${kind}-${desktop}-linux"
	id=$(gh api "repos/$repo/actions/artifacts?per_page=100" \
		-q ".artifacts[] | select(.name == \"$name\") | .id" | head -1)
	if [ -z "$id" ]; then
		echo "artifact not found: $name" >&2
		continue
	fi

	url=$(curl -sI -H "Authorization: token $token" \
		"https://api.github.com/repos/$repo/actions/artifacts/$id/zip" |
		tr -d '\r' | awk 'tolower($1) == "location:" {print $2}')
	[ -n "$url" ] || { echo "no download url for $name" >&2; exit 1; }

	aria2c -c -x8 -s8 -k1M --file-allocation=none \
		-o "${name}.zip" "$url"
	unzip -o -q "${name}.zip" -d "$kind"
	rm -f "${name}.zip"
done

# The archives keep the artifact's file names (boot.img / rootfs.img).
[ -f boot/boot.img ] || { echo "boot.img missing after unzip" >&2; exit 1; }
[ -f rootfs/rootfs.img ] || { echo "rootfs.img missing after unzip" >&2; exit 1; }
mv -f boot/boot.img boot.img
mv -f rootfs/rootfs.img rootfs.img
rmdir boot rootfs 2>/dev/null || true

echo
echo "✓ $dest/boot.img  ($(du -h boot.img | cut -f1))"
echo "✓ $dest/rootfs.img ($(du -h rootfs.img | cut -f1))"
