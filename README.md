# ffmpeg-builds

LGPL builds of [FFmpeg](https://ffmpeg.org), and the complete corresponding
source for each one.

FFmpeg is licensed under the LGPL. Redistributing an LGPL binary carries a duty
to make available the exact source it was built from, and this repository
discharges that duty for the FFmpeg binaries distributed with our software.

Every build here is configured **`--disable-gpl --disable-nonfree`** and links
**no GPL-only component** — no x264, no x265, no GPL-licensed filters.

---

## Releases

One release per FFmpeg version, carrying every platform's binaries and the
source they were built from.

| | |
| --- | --- |
| `ffmpeg-<version>-<platform>-lgpl.tar.xz` | `ffmpeg` and `ffprobe` |
| `ffmpeg-<version>-source-<origin>.tar.gz` | the complete corresponding source |
| `buildconf-<platform>.txt` | `ffmpeg -buildconf`, taken from the binary itself |
| `SHA256SUMS` | checksums for every asset above |

### Verifying a download

```sh
curl -LO https://github.com/bhavyadeep-purswani/ffmpeg-builds/releases/download/n9.0.1-1/SHA256SUMS
curl -LO https://github.com/bhavyadeep-purswani/ffmpeg-builds/releases/download/n9.0.1-1/ffmpeg-n9.0.1-darwin-arm64-lgpl.tar.xz
shasum -a 256 -c SHA256SUMS --ignore-missing
```

## Licensing

⚠️ **The LGPL version is not the same for every platform.** The binary is the
authority: run it with `-L` and it states its own terms. The table is read off
that.

| platform | licence | origin |
| --- | --- | --- |
| `darwin-arm64` | LGPL-2.1-or-later | built here |
| `darwin-x86_64` | LGPL-2.1-or-later | built here |
| `linux-x86_64` | LGPL-3.0-or-later | [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds) |
| `linux-arm64` | LGPL-3.0-or-later | BtbN/FFmpeg-Builds |
| `win32-x86_64` | LGPL-3.0-or-later | BtbN/FFmpeg-Builds |

The builds made here omit `--enable-version3`, so they remain LGPL-2.1. The
upstream builds enable it — they need it for `libopencore-amrnb` and
`libopencore-amrwb` — which makes them LGPL-3.0.

Both licence texts are in [`licences/`](licences/). Individual FFmpeg components
carry other permissive licences (BSD, ISC, MIT); a combined build is distributed
under the LGPL version its row names.

## Corresponding source

**Builds made here** link four libraries, and the source archive contains each
at the exact commit compiled, together with the build script:

| | |
| --- | --- |
| FFmpeg | `n9.0.1` |
| libaom | `v3.14.1` |
| SVT-AV1 | `v4.1.0` |
| libopus | `v1.6.1` |

**Upstream builds** link 45 libraries. `ffmpeg -buildconf` records which are
enabled but not at what version; the upstream build scripts pin each one by
repository and commit. The source archive therefore contains those scripts at
the commit that produced the build, plus every dependency's tree at the commit
they name — 111 archives in total, covering both linked libraries and the
toolchain used to produce them.

## Building

```sh
./build-ffmpeg-macos.sh /tmp/out             # host architecture
ARCH=x86_64 ./build-ffmpeg-macos.sh /tmp/out # cross-compile
```

The script is included in every source archive for the builds made here. It
pins each dependency to a tag, asserts the resulting binary carries the encoders
it is supposed to, and refuses a build whose `ffmpeg -L` disagrees with the
licence it claims.

## Reporting a problem

If you have received a binary whose source you cannot find here, please open an
issue. An incomplete offer of source is a defect and we would like to fix it.
