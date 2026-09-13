#!/usr/bin/env bash
# Build the LGPL macOS arm64 FFmpeg that  says must be built, not downloaded.
#
# ⚠️ THIS SCRIPT IS THE RECIPE. Its output is not pinned in `toolchain.py` until
# somebody runs it, hosts the binary *and its corresponding source* , and records the SHA-256. H-an earlier revision says
# plainly that an earlier revision did not: publishing a binary needs somewhere to publish it,
# and this repository has no release host and no remote.
#
# Why a build at all: no LGPL macOS arm64 FFmpeg prebuild exists . Every convenient one — evermeet, OSXExperimental — is
# `--enable-gpl`, which our licence policy forbids and the licence gate denies. an earlier revision's pin is
# one of those, flagged `shippable: False`, and it is a development convenience
# only: the packaging step refuses it without `--allow-unshippable-ffmpeg`.
#
# The configure line below is not a suggestion. Four encoders are load-bearing
# and each is named by a decision:
#
#   libaom-av1    keyframes and sprites (`-cpu-used` is a libaom option)
#   libsvtav1     the proxy             (`-preset` is an SVT-AV1 option)
#   libopus       the proxy's audio
#   flac          the audio artefact
#
# Both AV1 encoders in one build, because  and  use different options
# of different encoders and the intake stage refuses to substitute one for the other .
#
# Usage:
#   ./build-ffmpeg-macos.sh /tmp/ffmpeg-build
#   python the toolchain table pin --platform darwin-arm64 --from /tmp/ffmpeg-build/out

set -euo pipefail

# ── which architecture ──────────────────────────────────────────────────────
# ⛔ **Both macOS architectures are built HERE, on one machine, by
# cross-compiling** . The obvious reading of "build the macOS x64
# FFmpeg on the `macos-15-intel` runner" costs ~200 billed Actions minutes at
# macOS's 10× multiplier — most of a follow-up's entire budget on one binary.
# Apple's toolchain cross-compiles to x86_64 natively (it is how universal
# binaries are made) and Rosetta 2 then *runs* the result, so the same machine
# can produce the binary AND assert its encoders and its `ffmpeg -L` — which is
# the part that matters, and the part a runner would have given us anyway.
#
# `ARCH=x86_64 ./build-ffmpeg-macos.sh /tmp/out-x64`
ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in
  arm64|aarch64) ARCH=arm64 ;;
  x86_64|amd64)  ARCH=x86_64 ;;
  *) echo "unknown ARCH=$ARCH (want arm64 or x86_64)"; exit 1 ;;
esac
HOST_ARCH="$(uname -m)"
[ "$HOST_ARCH" = "aarch64" ] && HOST_ARCH=arm64

PREFIX="${1:-$PWD/.build/ffmpeg-macos-$ARCH}"
SRC="$PREFIX/src"
OUT="$PREFIX/out"
mkdir -p "$SRC" "$OUT"

# The flags every stage needs, so a cross build cannot half-happen: cmake gets
# `CMAKE_OSX_ARCHITECTURES`, FFmpeg's hand-rolled configure gets the arch and an
# explicit `--enable-cross-compile` when the target is not the host.
# ⚠️ **`CMAKE_OSX_ARCHITECTURES` alone is not enough and the first cross build
# proved it**: libaom went on compiling its NEON sources for an x86_64 target
# (`unknown type name 'int16x4_t'`) because it selects its assembly from
# `AOM_TARGET_CPU`, and SVT-AV1 selects from `CMAKE_SYSTEM_PROCESSOR`. Each
# project reads a different variable, so all three are set rather than the one
# that looks canonical.
CMAKE_ARCH_ARGS=(
  -DCMAKE_OSX_ARCHITECTURES="$ARCH"
  -DCMAKE_SYSTEM_PROCESSOR="$ARCH"
  -DAOM_TARGET_CPU="$([ "$ARCH" = arm64 ] && echo arm64 || echo x86_64)"
)
FF_ARCH_ARGS=(--arch="$ARCH")
if [ "$ARCH" != "$HOST_ARCH" ]; then
  FF_ARCH_ARGS+=(--enable-cross-compile --target-os=darwin
                 --cc="clang -arch $ARCH" --cxx="clang++ -arch $ARCH")
  export CFLAGS="-arch $ARCH ${CFLAGS:-}"
  export CXXFLAGS="-arch $ARCH ${CXXFLAGS:-}"
  export LDFLAGS="-arch $ARCH ${LDFLAGS:-}"
  echo "== cross-compiling $HOST_ARCH -> $ARCH"
fi

# Pinned versions.
#
# ⚠️ this project moved FFmpeg 7.1.1 → n9.0.1 and the three libraries with it. The reason
# is consistency, not novelty: every *other* entry in `toolchain.py`'s table is
# already 9.0.1 (BtbN's linux-x86_64 and linux-arm64 LGPL builds are
# `ffmpeg-n9.0.1-…-lgpl`, and an earlier revision's macOS development pin is Riedl's 9.0.1), so
# a 7.1.1 macOS build would have made the one platform we build ourselves the
# only one on a different major. The libraries are the versions contemporaneous
# with n9.0.1 (tagged 2026-08-12): aom 3.14.1, SVT-AV1 4.1.0, opus 1.6.1.
#
# A build whose inputs float is a build whose output cannot be reproduced, and
#  requires us to host the *corresponding* source — which means knowing
# exactly which source it was. Every one of these is a git tag, not a branch.
FFMPEG_VERSION="${FFMPEG_VERSION:-9.0.1}"
AOM_VERSION="${AOM_VERSION:-v3.14.1}"
SVT_VERSION="${SVT_VERSION:-v4.1.0}"
OPUS_VERSION="${OPUS_VERSION:-v1.6.1}"

command -v cmake >/dev/null || { echo "cmake is required (brew install cmake)"; exit 1; }
command -v nasm  >/dev/null || { echo "nasm is required (brew install nasm)";  exit 1; }
command -v pkg-config >/dev/null || { echo "pkg-config is required"; exit 1; }

export PKG_CONFIG_PATH="$OUT/lib/pkgconfig"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"

# ── libaom (BS-Clause + patent grant) ────────────────────────────────────
if [ ! -f "$OUT/lib/pkgconfig/aom.pc" ]; then
  rm -rf "$SRC/aom"
  git clone --depth 1 --branch "$AOM_VERSION" https://aomedia.googlesource.com/aom "$SRC/aom"
  cmake -S "$SRC/aom" -B "$SRC/aom-build" -DCMAKE_INSTALL_PREFIX="$OUT" "${CMAKE_ARCH_ARGS[@]}" \
    -DENABLE_TESTS=0 -DENABLE_EXAMPLES=0 -DENABLE_DOCS=0 -DBUILD_SHARED_LIBS=0 \
    -DCMAKE_BUILD_TYPE=Release
  cmake --build "$SRC/aom-build" --parallel && cmake --install "$SRC/aom-build"
fi

# ── SVT-AV1 (BS-Clause-Clear + patent grant) ─────────────────────────────
if [ ! -f "$OUT/lib/pkgconfig/SvtAv1Enc.pc" ]; then
  rm -rf "$SRC/svt"
  git clone --depth 1 --branch "$SVT_VERSION" https://gitlab.com/AOMediaCodec/SVT-AV1.git "$SRC/svt"
  cmake -S "$SRC/svt" -B "$SRC/svt-build" -DCMAKE_INSTALL_PREFIX="$OUT" "${CMAKE_ARCH_ARGS[@]}" \
    -DBUILD_SHARED_LIBS=0 -DBUILD_TESTING=0 -DCMAKE_BUILD_TYPE=Release
  cmake --build "$SRC/svt-build" --parallel && cmake --install "$SRC/svt-build"
fi

# ── libopus (BS-Clause) ──────────────────────────────────────────────────
if [ ! -f "$OUT/lib/pkgconfig/opus.pc" ]; then
  rm -rf "$SRC/opus"
  git clone --depth 1 --branch "$OPUS_VERSION" https://github.com/xiph/opus.git "$SRC/opus"
  cmake -S "$SRC/opus" -B "$SRC/opus-build" -DCMAKE_INSTALL_PREFIX="$OUT" "${CMAKE_ARCH_ARGS[@]}" \
    -DBUILD_SHARED_LIBS=0 -DCMAKE_BUILD_TYPE=Release
  cmake --build "$SRC/opus-build" --parallel && cmake --install "$SRC/opus-build"
fi

# ── FFmpeg, LGPL-2.1-or-later ───────────────────────────────────────────────
# `--disable-gpl --disable-nonfree` are 's, and they are the whole point:
# no x264, no x265, no GPL filters. FLAC is FFmpeg's own native encoder and
# needs no external library.
if [ ! -d "$SRC/ffmpeg" ]; then
  git clone --depth 1 --branch "n$FFMPEG_VERSION" https://github.com/FFmpeg/FFmpeg.git "$SRC/ffmpeg"
fi
cd "$SRC/ffmpeg"
# ⛔ **`--enable-version3` is NOT here, and this project removed it.** It was in this
# recipe until the first real build, which reported `ffmpeg -L` as *"the GNU
# Lesser General Public License … either version 3"* — while , this
# repository's `toolchain.py` table and the third-party notice all
# say **LGPL-2.1-or-later**. The flag only admits components that are LGPLv3
# (libopencore-amr and friends) and none of the four encoders  to  pin
# is one: libaom is BS-Clause, SVT-AV1 BS-Clause-Clear, libopus
# BS-Clause, and FLAC is FFmpeg's own native encoder. So it bought nothing
# and made the binary's own licence statement disagree with the record we
# redistribute beside it. FFmpeg's `-L` output is the check, and it is asserted
# below.
./configure \
  --prefix="$OUT" \
  "${FF_ARCH_ARGS[@]}" \
  --disable-gpl \
  --disable-nonfree \
  --enable-libaom \
  --enable-libsvtav1 \
  --enable-libopus \
  --enable-encoder=flac \
  --enable-static --disable-shared \
  --disable-debug --disable-doc \
  --extra-cflags="-I$OUT/include" \
  --extra-ldflags="-L$OUT/lib"
make -j"$(sysctl -n hw.ncpu)"
make install

# ── the assertion that makes this worth running ─────────────────────────────
# ⭐ An x86_64 build on Apple Silicon runs under Rosetta 2, so the encoder set
# and `ffmpeg -L` are asserted on the ACTUAL BINARY rather than inferred from
# the configure line. `-buildconf` says what was asked for; `-L` says what
# FFmpeg thinks it became, and this project found those two disagreeing.
run_ffmpeg() {
  if [ "$ARCH" != "$HOST_ARCH" ]; then arch "-$ARCH" "$OUT/bin/ffmpeg" "$@"; else "$OUT/bin/ffmpeg" "$@"; fi
}
# A cross build we cannot execute can still be checked for its architecture, and
# saying which check ran is the difference between a pass and a claim.
file "$OUT/bin/ffmpeg" | grep -q "$ARCH" \
  || { echo "the built ffmpeg is not $ARCH: $(file "$OUT/bin/ffmpeg")"; exit 1; }
run_ffmpeg -hide_banner -encoders 2>/dev/null | grep -E ' (libaom-av1|libsvtav1|libopus|flac) ' \
  || { echo "the build is missing a pinned encoder "; exit 1; }
run_ffmpeg -hide_banner -buildconf 2>&1 | grep -q -- '--disable-gpl' \
  || { echo "the build is not LGPL — refusing "; exit 1; }
# `if !` rather than `… && { exit 1; }`: under `set -e` a trailing `&&` whose
# left side fails takes the whole script down, which would turn the *good* case
# (no `--enable-version3`) into a failed build.
if run_ffmpeg -hide_banner -buildconf 2>&1 | grep -q -- '--enable-version3'; then
  echo "the build is LGPLv3 — refusing: the record says 2.1 "; exit 1
fi
# ⭐ And the binary's own statement, which is the one a reader of the licence
# will see. `-buildconf` says what we asked for; `-L` says what FFmpeg thinks it
# became, and this project found those two disagreeing.
run_ffmpeg -hide_banner -L 2>&1 | grep -q 'Lesser General Public License' \
  || { echo "ffmpeg -L does not say LGPL — refusing "; exit 1; }
# ⚠️ `-L` hard-wraps its paragraph, and where it wraps depends on the version
# string: with `--enable-version3` it reads "…either version 3 of the License"
# on one line, without it "…either\nversion 2.1 of the License". So the pattern
# is the half that cannot straddle the break. Grepping for "either version 2.1"
# passed the LGPLv3 build and failed the correct one — found by running it.
run_ffmpeg -hide_banner -L 2>&1 | grep -q 'version 2\.1 of the License' \
  || { echo "ffmpeg -L does not say LGPL 2.1 — the record and the binary disagree "; exit 1; }

echo
echo "built: $OUT/bin/ffmpeg  ($ARCH)"
echo "LGPL-2.1-or-later, with libaom-av1 + libsvtav1 + libopus + flac."
echo
echo " is not finished here. Redistributing FFmpeg means owing its terms:"
echo "  1. ship the LGPL-2.1 text and an attribution notice (the third-party notice)"
echo "  2. host the EXACT corresponding source for this build, ourselves"
echo "  3. record the URL and SHA-256 in the toolchain table with shippable: True"
echo "Steps 2 and 3 need a release host. Until they are done the pin stays GPL"
echo 'and shippable: False, and check-shippable keeps the artefact off the ship.'
