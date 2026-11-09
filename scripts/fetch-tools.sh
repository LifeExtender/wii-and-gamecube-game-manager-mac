#!/bin/sh
# Downloads Wiimms ISO Tools, checks them against a known hash and prepares them for bundling.
# See Helpers/PROVENANCE.txt for why the binaries need repairing first.
set -eu

VERSION="v3.05a-r8638"
URL="https://wit.wiimm.de/download/wit-$VERSION-mac.tar.gz"
SHA256="670fd1920eb0390ecdc2553942df71f0ced43c63c8e83588a23705b569d25213"

DEST="$(cd "$(dirname "$0")/.." && pwd)/Helpers"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:?}"' EXIT

curl -fsSL "$URL" -o "$WORK/wit.tar.gz"
echo "$SHA256  $WORK/wit.tar.gz" | shasum -a 256 -c - >/dev/null
tar -xzf "$WORK/wit.tar.gz" -C "$WORK"

for tool in wit wwt; do
    python3 - "$WORK/wit-$VERSION-mac/bin/$tool" "$WORK/$tool" <<'PY'
import struct
import sys

source, output = sys.argv[1:3]
blob = open(source, "rb").read()
names = {0x01000007: "x86_64", 0x0100000C: "arm64"}
for index in range(struct.unpack(">I", blob[4:8])[0]):
    cpu, _, offset, size, _ = struct.unpack(">5I", blob[8 + index * 20 : 28 + index * 20])
    with open(f"{output}.{names[cpu]}", "wb") as slice_file:
        slice_file.write(blob[offset : offset + size])
PY
    for arch in arm64 x86_64; do
        chmod 755 "$WORK/$tool.$arch"
        codesign -f -s - "$WORK/$tool.$arch" 2>/dev/null
    done
    lipo -create "$WORK/$tool.arm64" "$WORK/$tool.x86_64" -output "$DEST/$tool"
    codesign -f -s - "$DEST/$tool" 2>/dev/null
done

echo "Installed wit and wwt $VERSION in Helpers/"
