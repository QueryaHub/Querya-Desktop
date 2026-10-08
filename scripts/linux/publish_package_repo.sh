#!/usr/bin/env bash
# Publish the release .deb / .rpm to the signed APT + DNF repository.
#
# Usage:
#   ./scripts/linux/publish_package_repo.sh <path/to/*.deb> <path/to/*.rpm>
#
# Environment:
#   PACKAGE_REPO_URL      git URL of the repository served as repo.querya.app
#                         (token embedded for HTTPS), e.g. QueryaHub/repo
#   PACKAGE_REPO_BRANCH   branch that is served (default: gh-pages)
#   GPG_KEY_ID            fingerprint of the signing key (already imported)
#
# Layout written to the branch:
#   gpg.key                       public key (ASCII armor)
#   apt/pool/main/*.deb           every published .deb
#   apt/dists/stable/...          Packages, Release, InRelease, Release.gpg
#   rpm/*.rpm, rpm/repodata/      every published .rpm, signed repomd.xml
#   rpm/querya.repo               file for `dnf config-manager --add-repo`
#
# Requires: git, gpg, apt-utils (apt-ftparchive), createrepo-c, rpm.
set -euo pipefail

DEB="${1:?path to .deb}"
RPM="${2:?path to .rpm}"
: "${PACKAGE_REPO_URL:?}"
: "${GPG_KEY_ID:?}"
BRANCH="${PACKAGE_REPO_BRANCH:-gh-pages}"
BASE_URL="${PACKAGE_REPO_BASE_URL:-https://repo.querya.app}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/querya-pkgrepo.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
SITE="$WORK/site"

if git ls-remote --exit-code --heads "$PACKAGE_REPO_URL" "$BRANCH" >/dev/null 2>&1; then
  git clone --quiet --depth 1 --branch "$BRANCH" "$PACKAGE_REPO_URL" "$SITE"
else
  git init --quiet "$SITE"
  git -C "$SITE" checkout --quiet -b "$BRANCH"
  git -C "$SITE" remote add origin "$PACKAGE_REPO_URL"
fi

gpg --batch --armor --export "$GPG_KEY_ID" > "$SITE/gpg.key"

# ---- APT -------------------------------------------------------------------
APT="$SITE/apt"
mkdir -p "$APT/pool/main" "$APT/dists/stable/main/binary-amd64"
cp -f "$DEB" "$APT/pool/main/"
(
  cd "$APT"
  apt-ftparchive packages pool > dists/stable/main/binary-amd64/Packages
  gzip -9kf dists/stable/main/binary-amd64/Packages
  apt-ftparchive \
    -o APT::FTPArchive::Release::Origin=Querya \
    -o APT::FTPArchive::Release::Label=Querya \
    -o APT::FTPArchive::Release::Suite=stable \
    -o APT::FTPArchive::Release::Codename=stable \
    -o APT::FTPArchive::Release::Architectures=amd64 \
    -o APT::FTPArchive::Release::Components=main \
    release dists/stable > dists/stable/Release
  gpg --batch --yes --default-key "$GPG_KEY_ID" \
    --clearsign -o dists/stable/InRelease dists/stable/Release
  gpg --batch --yes --default-key "$GPG_KEY_ID" \
    --armor --detach-sign -o dists/stable/Release.gpg dists/stable/Release
)

# ---- DNF -------------------------------------------------------------------
RPMDIR="$SITE/rpm"
mkdir -p "$RPMDIR"
cp -f "$RPM" "$RPMDIR/"
rpmsign_conf="$WORK/rpmmacros"
printf '%%_gpg_name %s\n%%__gpg %s\n' "$GPG_KEY_ID" "$(command -v gpg)" > "$rpmsign_conf"
HOME_RPM="$WORK/home"
mkdir -p "$HOME_RPM"
cp "$rpmsign_conf" "$HOME_RPM/.rpmmacros"
HOME="$HOME_RPM" GNUPGHOME="${GNUPGHOME:-$HOME/.gnupg}" rpmsign --addsign "$RPMDIR"/*.rpm
createrepo_c --update "$RPMDIR"
gpg --batch --yes --default-key "$GPG_KEY_ID" \
  --armor --detach-sign -o "$RPMDIR/repodata/repomd.xml.asc" "$RPMDIR/repodata/repomd.xml"
cat > "$RPMDIR/querya.repo" <<REPO
[querya]
name=Querya Desktop
baseurl=$BASE_URL/rpm
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$BASE_URL/gpg.key
REPO

# ---- push ------------------------------------------------------------------
cd "$SITE"
touch .nojekyll
git add -A
if git diff --cached --quiet; then
  echo "package repository already up to date"
  exit 0
fi
git -c user.name="querya-release-bot" -c user.email="release-bot@querya.app" \
  commit --quiet -m "repo: publish $(basename "$DEB")"
git push --quiet origin "HEAD:$BRANCH"
echo "published $(basename "$DEB") and $(basename "$RPM") to $BASE_URL"
