#!/usr/bin/env bash
# Pack the Flutter Linux release bundle into a .deb.
#
#   flutter build linux --release
#   scripts/package-deb.sh
#
# Output: packaging/out/jterm_<version>_amd64.deb
# A tag named vX.Y.Z (GitHub Actions) overrides the version from pubspec.yaml.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

version="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -1)"
version="${version%%+*}"
version="${version%%-*}"
if [[ "${GITHUB_REF_NAME:-}" == v* ]]; then
  version="${GITHUB_REF_NAME#v}"
  version="${version%%+*}"
fi

arch="amd64"
bundle="${1:-build/linux/x64/release/bundle}"
if [[ ! -x "$bundle/jterm" ]]; then
  echo "找不到 $bundle/jterm，请先执行: flutter build linux --release" >&2
  exit 1
fi

stage="packaging/out/jterm_${version}_${arch}"
rm -rf "$stage"
mkdir -p \
  "$stage/DEBIAN" \
  "$stage/usr/bin" \
  "$stage/usr/lib/jterm" \
  "$stage/usr/share/applications" \
  "$stage/usr/share/icons/hicolor"

cp -a "$bundle/." "$stage/usr/lib/jterm/"
chmod 755 "$stage/usr/lib/jterm/jterm"
cp "packaging/icons/hicolor/256x256/apps/dev.jterm.jterm.png" "$stage/usr/lib/jterm/jterm.png"
ln -s /usr/lib/jterm/jterm "$stage/usr/bin/jterm"
cp packaging/jterm.desktop "$stage/usr/share/applications/dev.jterm.jterm.desktop"
cp -a packaging/icons/hicolor/. "$stage/usr/share/icons/hicolor/"
find "$stage" -type d -exec chmod 755 {} +
find "$stage" -type f -exec chmod 644 {} +
chmod 755 "$stage/usr/lib/jterm/jterm"

cat > "$stage/DEBIAN/control" << EOF
Package: jterm
Version: ${version}
Section: net
Priority: optional
Architecture: ${arch}
Maintainer: jiang-mingjun97 <1397595134@qq.com>
Depends: libgtk-3-0t64 | libgtk-3-0, libc6 (>= 2.35), hicolor-icon-theme
Description: SSH and terminal client
 JTerm is a Flutter desktop SSH client for Linux.
EOF

mkdir -p packaging/out
deb="packaging/out/jterm_${version}_${arch}.deb"
dpkg-deb --root-owner-group --build "$stage" "$deb"
(
  cd packaging/out
  sha256sum "jterm_${version}_${arch}.deb" > "jterm_${version}_${arch}.deb.sha256"
)
echo "已生成 $deb"
