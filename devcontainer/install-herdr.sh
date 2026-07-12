#!/usr/bin/env sh
set -eu

HERDR_VERSION="${HERDR_VERSION:-0.7.1}"
HERDR_SHA256_AMD64="${HERDR_SHA256_AMD64:-b965acaffc2c22f54b6e6c64af7cf8e98a3f4ac2622630a0599c67a4b9d8a654}"
HERDR_SHA256_ARM64="${HERDR_SHA256_ARM64:-3d757ac30c631e79dc45038c3ecc6423fe13a89f9cffa0f415aedd2c27f1576c}"
HERDR_INSTALL_DIR="${HERDR_INSTALL_DIR:-/usr/local/bin}"

arch="${TARGETARCH:-$(uname -m)}"
case "$arch" in
  amd64|x86_64)
    asset="herdr-linux-x86_64"
    checksum="$HERDR_SHA256_AMD64"
    ;;
  arm64|aarch64)
    asset="herdr-linux-aarch64"
    checksum="$HERDR_SHA256_ARM64"
    ;;
  *)
    echo "Unsupported architecture for Herdr: $arch" >&2
    exit 1
    ;;
esac

tmp="$(mktemp "${TMPDIR:-/tmp}/herdr.XXXXXX")"
url="https://github.com/ogulcancelik/herdr/releases/download/v${HERDR_VERSION#v}/${asset}"

cleanup() {
  rm -f "$tmp"
}
trap cleanup EXIT INT TERM

echo "Installing Herdr ${HERDR_VERSION#v} from $url"
curl -fsSL "$url" -o "$tmp"
printf '%s  %s\n' "$checksum" "$tmp" | sha256sum -c -

mkdir -p "$HERDR_INSTALL_DIR"
cp "$tmp" "$HERDR_INSTALL_DIR/herdr"
chmod 0755 "$HERDR_INSTALL_DIR/herdr"

"$HERDR_INSTALL_DIR/herdr" --version
