#!/usr/bin/env bash
# Push querya-desktop PKGBUILD to AUR (used by Release CI and aur-publish workflow).
#
# Prerequisites: ssh-agent loaded with AUR key; docker available for makepkg --printsrcinfo.
#
# Usage:
#   aur_publish.sh <version> [release_tag]
#
# release_tag — GitHub Release tag (tries release_tag, version, vversion for asset URL).
set -euo pipefail

VERSION="${1:?version required}"
RELEASE_TAG="${2:-$VERSION}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE="$ROOT/packaging/linux/aur"
AUR_REPO="${AUR_REPO:-querya-desktop}"
WORK="$ROOT/aur-repo"
ZIP="Querya-Desktop-${VERSION}-linux.zip"
REPO="${GITHUB_REPOSITORY:-QueryaHub/Querya-Desktop}"

download_release_zip() {
  local tag url
  for tag in "$RELEASE_TAG" "$VERSION" "v${VERSION}"; do
    url="https://github.com/${REPO}/releases/download/${tag}/${ZIP}"
    echo "Fetching ${url}"
    if curl -fsSL -o "$ZIP" "$url"; then
      echo "Downloaded from tag ${tag}"
      return 0
    fi
    echo "retry with next tag candidate..."
    sleep 5
  done
  return 1
}

echo "AUR publish: pkgver=${VERSION} release_tag=${RELEASE_TAG}"

cd "$ROOT"
for attempt in 1 2 3 4 5 6; do
  if download_release_zip; then
    break
  fi
  if [ "$attempt" -eq 6 ]; then
    echo "error: could not download ${ZIP}" >&2
    exit 1
  fi
  echo "retry ${attempt}..."
  sleep 10
done

ZIP_SHA="$(sha256sum "$ZIP" | awk '{print $1}')"
DESKTOP_SHA="$(sha256sum "$TEMPLATE/querya_desktop.desktop" | awk '{print $1}')"
PNG_SHA="$(sha256sum "$TEMPLATE/querya_desktop.png" | awk '{print $1}')"

mkdir -p ~/.ssh
ssh-keyscan -t rsa,ecdsa,ed25519 aur.archlinux.org >> ~/.ssh/known_hosts 2>/dev/null

rm -rf "$WORK"
if ! git clone "ssh://aur@aur.archlinux.org/${AUR_REPO}.git" "$WORK" 2>/dev/null; then
  mkdir -p "$WORK"
  git -C "$WORK" init
  git -C "$WORK" remote add origin "ssh://aur@aur.archlinux.org/${AUR_REPO}.git"
fi

cp "$TEMPLATE/PKGBUILD" "$WORK/PKGBUILD"
cp "$TEMPLATE/querya_desktop.desktop" "$WORK/querya_desktop.desktop"
cp "$TEMPLATE/querya_desktop.png" "$WORK/querya_desktop.png"

cd "$WORK"
sed -i "s/^pkgver=.*/pkgver=${VERSION}/" PKGBUILD
sed -i "s/^pkgrel=.*/pkgrel=1/" PKGBUILD
sed -i "s/^sha256sums=.*/sha256sums=('${ZIP_SHA}' '${DESKTOP_SHA}' '${PNG_SHA}')/" PKGBUILD

out="$WORK/.SRCINFO"
docker run --rm \
  -v "$WORK:/pkg" \
  archlinux:latest \
  bash -lc '
    set -euo pipefail
    pacman -Syu --noconfirm --needed archlinux-keyring pacman base-devel >/dev/null 2>&1
    useradd -m -s /bin/bash builduser
    chown -R builduser:builduser /pkg
    runuser -u builduser -- env HOME=/home/builduser bash -lc "cd /pkg && makepkg --printsrcinfo"
  ' > "$out"
sudo chown -R "$(id -u):$(id -g)" "$WORK" 2>/dev/null || true
test -s "$out"
grep -qE "^pkgbase[[:space:]]*=" "$out" || { echo "::error::Invalid .SRCINFO"; head -50 "$out"; exit 1; }

git config user.email "github-actions[bot]@users.noreply.github.com"
git config user.name "github-actions[bot]"
git add PKGBUILD .SRCINFO querya_desktop.desktop querya_desktop.png
if git diff --cached --quiet; then
  echo "No changes to commit"
  exit 0
fi
git commit -m "chore: ${VERSION}"
git push origin HEAD:master

echo "AUR ${AUR_REPO} updated to ${VERSION}"
