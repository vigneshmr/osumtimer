#!/bin/bash
# Cuts a release: tags the commit, publishes the .dmg as a GitHub release, and
# points the Homebrew tap (vigneshmr/homebrew-osumtimer) at it. Anyone who has
# run `brew tap vigneshmr/osumtimer` then gets the new version from
# `brew upgrade`, which is the whole reason the tap exists.
#
# Idempotent per version: an existing tag, release or asset is reused, so a
# run that died halfway can simply be repeated.
set -euo pipefail

VERSION="${VERSION:?set VERSION, e.g. make release VERSION=1.1.0}"
TAP_REPO="${TAP_REPO:-vigneshmr/homebrew-osumtimer}"
TAG="v$VERSION"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG="$ROOT/build/OsumTimer-$VERSION.dmg"
TAP_DIR="$ROOT/build/tap"

cd "$ROOT"
APP_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

if [ -n "$(git status --porcelain)" ]; then
	echo "error: working tree is dirty — commit or stash first." >&2
	exit 1
fi

echo "==> Packaging $VERSION"
VERSION="$VERSION" "$ROOT/scripts/package.sh"

echo "==> Tagging $TAG"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
	echo "    (tag exists, reusing)"
else
	git tag -a "$TAG" -m "OsumTimer $VERSION"
fi
git push origin main "$TAG"

echo "==> Publishing GitHub release"
if gh release view "$TAG" >/dev/null 2>&1; then
	gh release upload "$TAG" "$DMG" --clobber
else
	gh release create "$TAG" "$DMG" --title "OsumTimer $VERSION" --generate-notes
fi

SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"

echo "==> Updating tap $TAP_REPO"
rm -rf "$TAP_DIR"
if ! gh repo clone "$TAP_REPO" "$TAP_DIR" -- --depth 1 >/dev/null 2>&1; then
	gh repo create "$TAP_REPO" --public \
		--description "Homebrew tap for OsumTimer" >/dev/null
	git init -q -b main "$TAP_DIR"
	git -C "$TAP_DIR" remote add origin "git@github.com:$TAP_REPO.git"
fi
mkdir -p "$TAP_DIR/Casks"

cat > "$TAP_DIR/Casks/osumtimer.rb" <<CASK
cask "osumtimer" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$APP_REPO/releases/download/v#{version}/OsumTimer-#{version}.dmg"
  name "OsumTimer"
  desc "Menu bar timer you drive by typing"
  homepage "https://github.com/$APP_REPO"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "OsumTimer.app"

  # The bundle is ad-hoc signed, not notarized, so Gatekeeper would refuse a
  # quarantined copy outright. Stripping the flag is what the user would do by
  # hand anyway.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/OsumTimer.app"]
  end

  uninstall quit: "com.osumtimer.OsumTimer"

  zap trash: [
    "~/Library/Preferences/com.osumtimer.OsumTimer.plist",
    "~/Library/Application Support/OsumTimer",
  ]
end
CASK

cat > "$TAP_DIR/README.md" <<README
# homebrew-osumtimer

Homebrew tap for [OsumTimer](https://github.com/$APP_REPO), a menu bar timer for macOS.

\`\`\`sh
brew tap ${TAP_REPO%/homebrew-*}/${TAP_REPO#*/homebrew-}
brew trust ${TAP_REPO%/homebrew-*}/${TAP_REPO#*/homebrew-}
brew install osumtimer
\`\`\`

Casks here are written by \`make release\` in the app repo — edit them there.
README

git -C "$TAP_DIR" add -A
if git -C "$TAP_DIR" diff --cached --quiet; then
	echo "    (tap already at $VERSION)"
else
	git -C "$TAP_DIR" commit -q -m "osumtimer $VERSION"
	git -C "$TAP_DIR" push -q -u origin main
fi

echo
echo "Released OsumTimer $VERSION"
echo "  release: https://github.com/$APP_REPO/releases/tag/$TAG"
echo "  cask:    https://github.com/$TAP_REPO/blob/main/Casks/osumtimer.rb"
