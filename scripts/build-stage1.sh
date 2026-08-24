#!/usr/bin/env bash
#
# Cross-compile Lean 4 (runtime + stdlib + compiler) for aarch64-linux-android.
#
# Produces an Android libleanshared.so and a lean binary. Needs a HOST Lean of the
# same version to drive the build: Lean is written in Lean, and a cross-compiled
# stage0 cannot run on the build machine.
#
#   ./scripts/build-stage1.sh [--ndk PATH] [--host-toolchain PATH]

set -euo pipefail

LEAN_VERSION="4.33.0"
LIBUV_VERSION="v1.48.0"
OPENSSL_VERSION="openssl-3.5.0"
API="34"
ABI="arm64-v8a"
NDK="${ANDROID_NDK_HOME:-/opt/homebrew/share/android-ndk}"
HOST_TOOLCHAIN="${LEAN_HOST_TOOLCHAIN:-$HOME/.elan/toolchains/leanprover--lean4---v$LEAN_VERSION}"
BUILD="${BUILD_DIR:-build-stage1}"

while [ $# -gt 0 ]; do
  case "$1" in
    --ndk) NDK="$2"; shift 2 ;;
    --host-toolchain) HOST_TOOLCHAIN="$2"; shift 2 ;;
    --build-dir) BUILD="$2"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
die() { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

[ -d "$NDK" ] || die "NDK not found at $NDK"
[ -x "$HOST_TOOLCHAIN/bin/lean" ] || die "no host Lean at $HOST_TOOLCHAIN/bin/lean (elan toolchain for v$LEAN_VERSION)"

HOSTTAG="$(ls "$NDK/toolchains/llvm/prebuilt" | head -1)"
BIN="$NDK/toolchains/llvm/prebuilt/$HOSTTAG/bin"
SYSROOT="$BIN/../sysroot"
TOOLCHAIN="$NDK/build/cmake/android.toolchain.cmake"

mkdir -p "$BUILD"; BUILD="$(cd "$BUILD" && pwd)"

say "Configuration"
echo "  NDK:   $NDK"
echo "  host:  $HOST_TOOLCHAIN"
echo "  out:   $BUILD"

say "Fetching sources"
[ -d "$BUILD/lean4" ]  || git clone --depth 1 --branch "v$LEAN_VERSION" https://github.com/leanprover/lean4 "$BUILD/lean4" 2>&1 | tail -1
[ -d "$BUILD/libuv" ]  || git clone --depth 1 --branch "$LIBUV_VERSION" https://github.com/libuv/libuv "$BUILD/libuv" 2>&1 | tail -1
[ -d "$BUILD/openssl" ]|| git clone --depth 1 --branch "$OPENSSL_VERSION" https://github.com/openssl/openssl "$BUILD/openssl" 2>&1 | tail -1

say "Building libuv"
if [ ! -f "$BUILD/libuv-build/libuv.a" ]; then
  cmake -S "$BUILD/libuv" -B "$BUILD/libuv-build" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" -DANDROID_ABI="$ABI" \
    -DANDROID_PLATFORM="android-$API" -DCMAKE_BUILD_TYPE=Release \
    -DLIBUV_BUILD_TESTS=OFF -DBUILD_TESTING=OFF > "$BUILD/libuv.log" 2>&1 \
    && cmake --build "$BUILD/libuv-build" >> "$BUILD/libuv.log" 2>&1 || die "libuv failed, see $BUILD/libuv.log"
fi

say "Building OpenSSL"
if [ ! -f "$BUILD/openssl-install/lib/libcrypto.a" ]; then
  ( cd "$BUILD/openssl" && ANDROID_NDK_ROOT="$NDK" PATH="$BIN:$PATH" \
      ./Configure android-arm64 -D__ANDROID_API__=$API no-shared no-tests \
      --prefix="$BUILD/openssl-install" > "$BUILD/openssl.log" 2>&1 \
    && ANDROID_NDK_ROOT="$NDK" PATH="$BIN:$PATH" make -j8 >> "$BUILD/openssl.log" 2>&1 \
    && PATH="$BIN:$PATH" make install_dev >> "$BUILD/openssl.log" 2>&1 ) || die "openssl failed, see $BUILD/openssl.log"
fi

say "Writing cross-compilation shims"
# LEAN_CC takes a single executable path, so the target, sysroot, libuv headers and
# -fPIC cannot ride alongside it. Lake invokes $LEAN_CC directly rather than through
# leanc.sh, and Lean's CMake never folds CMAKE_C_FLAGS into it, so without this the
# NDK's --target/--sysroot never arrive and every object fails on sys/cdefs.h.
cat > "$BUILD/ndk-cc.sh" <<EOF
#!/usr/bin/env bash
exec $BIN/clang --target=aarch64-linux-android$API --sysroot=$SYSROOT -fPIC -I $BUILD/libuv/include "\$@"
EOF
chmod +x "$BUILD/ndk-cc.sh"

# Lake's bootstrap path picks libtool from System.Platform.isOSX, which reports the
# platform Lake itself was built for, not the target. On a macOS host that hands
# BSD libtool a set of ELF objects it cannot archive.
mkdir -p "$BUILD/shim"
cat > "$BUILD/shim/libtool" <<EOF
#!/usr/bin/env bash
AR="$BIN/llvm-ar"
out=""; filelist=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -static) shift ;;
    -o) out="\$2"; shift 2 ;;
    -filelist) filelist="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
rm -f "\$out"
exec "\$AR" rcs "\$out" @"\$filelist"
EOF
chmod +x "$BUILD/shim/libtool"

# Stage1 re-runs find_package and would otherwise resolve the HOST libuv.
mkdir -p "$BUILD/pkgcfg"
cat > "$BUILD/pkgcfg/libuv.pc" <<EOF
prefix=$BUILD/libuv
libdir=$BUILD/libuv-build
includedir=$BUILD/libuv/include
Name: libuv
Description: libuv for Android
Version: 1.48.0
Libs: -L\${libdir} -luv
Cflags: -I\${includedir}
EOF

# The build looks for <host>/lib/lean/libLake_shared.so, but elan ships .dylib on
# macOS. Additive symlinks, nothing overwritten.
for d in libLake_shared libInit_shared libleanshared libleanshared_1 libleanshared_2; do
  if [ -f "$HOST_TOOLCHAIN/lib/lean/$d.dylib" ] && [ ! -e "$HOST_TOOLCHAIN/lib/lean/$d.so" ]; then
    ln -s "$d.dylib" "$HOST_TOOLCHAIN/lib/lean/$d.so"
  fi
done

say "Patching stdlib.make.in for LEAN_CC"
# One-line upstream change: let the build supply a LEAN_CC wrapper.
MK="$BUILD/lean4/src/stdlib.make.in"
if ! grep -q "LEAN_CC_EXE" "$MK"; then
  python3 - "$MK" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
old='ifeq "${USE_LAKE}" "ON"\n  export LEAN_CC=${CMAKE_C_COMPILER}'
new='ifneq "${LEAN_CC_EXE}" ""\n  export LEAN_CC=${LEAN_CC_EXE}\nelse ifeq "${USE_LAKE}" "ON"\n  export LEAN_CC=${CMAKE_C_COMPILER}'
assert old in s, "stdlib.make.in shape changed"
open(p,'w').write(s.replace(old,new,1))
PY
fi

say "Configuring stage1"
rm -rf "$BUILD/stage"
PKG_CONFIG_PATH="$BUILD/pkgcfg" PKG_CONFIG_LIBDIR="$BUILD/pkgcfg" \
cmake -S "$BUILD/lean4" -B "$BUILD/stage" \
  -DSTAGE1_PREV_STAGE="$HOST_TOOLCHAIN" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" -DANDROID_ABI="$ABI" -DANDROID_PLATFORM="android-$API" \
  -DUSE_MIMALLOC=OFF -DUSE_GMP=OFF -DCMAKE_BUILD_TYPE=Release \
  -DSTAGE1_LEAN_CC_EXE="$BUILD/ndk-cc.sh" \
  -DSTAGE1_OPENSSL_ROOT_DIR="$BUILD/openssl-install" \
  -DSTAGE1_OPENSSL_USE_STATIC_LIBS=ON \
  -DSTAGE1_OPENSSL_CRYPTO_LIBRARY="$BUILD/openssl-install/lib/libcrypto.a" \
  -DSTAGE1_OPENSSL_SSL_LIBRARY="$BUILD/openssl-install/lib/libssl.a" \
  -DSTAGE1_OPENSSL_INCLUDE_DIR="$BUILD/openssl-install/include" \
  -DSTAGE1_LEANC_EXTRA_CC_FLAGS="--target=aarch64-linux-android$API --sysroot=$SYSROOT -fPIC -I$BUILD/libuv/include" \
  > "$BUILD/configure.log" 2>&1 || die "configure failed, see $BUILD/configure.log"

say "Building stage1 (long; 5k modules)"
# `lake` is a host build tool and does not link for Android; the libraries below are
# what matters, so its failure at the very end is expected and not fatal.
( cd "$BUILD/stage" && PATH="$BUILD/shim:$PATH" \
    PKG_CONFIG_PATH="$BUILD/pkgcfg" PKG_CONFIG_LIBDIR="$BUILD/pkgcfg" \
    make stage1 -j8 > "$BUILD/build.log" 2>&1 ) || true

SO="$BUILD/stage/stage1/lib/lean/libleanshared.so"
[ -f "$SO" ] || die "libleanshared.so was not produced, see $BUILD/build.log"

say "Result"
echo "  modules built: $(grep -c '✔' "$BUILD/build.log" || echo '?')"
echo "  $SO"
file "$SO" | sed 's/^.*: /  /'
echo
echo "  Next: https://github.com/saviorand/lean-android-compose builds an app on this."
