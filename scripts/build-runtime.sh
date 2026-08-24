#!/usr/bin/env bash
#
# Cross-compile the Lean 4 runtime for aarch64-linux-android.
#
# Produces libleanrt_android.a, a static library of Lean's C++ runtime built
# against Bionic. This is the runtime only: it does not bootstrap the compiler
# or build the Lean standard library.
#
#   ./scripts/build-runtime.sh [--ndk PATH] [--lean-version 4.33.0] [--api 34]

set -euo pipefail

LEAN_VERSION="4.33.0"
LIBUV_VERSION="v1.48.0"   # must match the GIT_TAG Lean pins in src/CMakeLists.txt
API="34"
ABI="arm64-v8a"
NDK="${ANDROID_NDK_HOME:-/opt/homebrew/share/android-ndk}"
BUILD="${BUILD_DIR:-build}"

while [ $# -gt 0 ]; do
  case "$1" in
    --ndk) NDK="$2"; shift 2 ;;
    --lean-version) LEAN_VERSION="$2"; shift 2 ;;
    --api) API="$2"; shift 2 ;;
    --build-dir) BUILD="$2"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
die() { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

[ -d "$NDK" ] || die "NDK not found at $NDK (set ANDROID_NDK_HOME or pass --ndk)"
TOOLCHAIN="$NDK/build/cmake/android.toolchain.cmake"
[ -f "$TOOLCHAIN" ] || die "no android.toolchain.cmake under $NDK"

HOSTTAG="$(ls "$NDK/toolchains/llvm/prebuilt" | head -1)"
BIN="$NDK/toolchains/llvm/prebuilt/$HOSTTAG/bin"
CXX="$BIN/aarch64-linux-android$API-clang++"
AR="$BIN/llvm-ar"
[ -x "$CXX" ] || die "no compiler for API $API at $CXX"

mkdir -p "$BUILD"
BUILD="$(cd "$BUILD" && pwd)"

say "Configuration"
echo "  NDK:      $NDK ($(grep -m1 Pkg.Revision "$NDK/source.properties" 2>/dev/null | cut -d= -f2 | tr -d ' '))"
echo "  compiler: $(basename "$CXX")"
echo "  Lean:     v$LEAN_VERSION"
echo "  libuv:    $LIBUV_VERSION"
echo "  output:   $BUILD"

say "Fetching sources"
[ -d "$BUILD/lean4" ] || git clone --depth 1 --branch "v$LEAN_VERSION" \
  https://github.com/leanprover/lean4 "$BUILD/lean4" 2>&1 | tail -1
[ -d "$BUILD/libuv" ] || git clone --depth 1 --branch "$LIBUV_VERSION" \
  https://github.com/libuv/libuv "$BUILD/libuv" 2>&1 | tail -1

say "Building libuv for $ABI"
# libuv carries its own `if(CMAKE_SYSTEM_NAME STREQUAL "Android")` branch, so the
# stock NDK toolchain file is all it needs. No patches.
if [ ! -f "$BUILD/libuv-build/libuv.a" ]; then
  cmake -S "$BUILD/libuv" -B "$BUILD/libuv-build" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DANDROID_ABI="$ABI" -DANDROID_PLATFORM="android-$API" \
    -DCMAKE_BUILD_TYPE=Release -DLIBUV_BUILD_TESTS=OFF -DBUILD_TESTING=OFF \
    > "$BUILD/libuv-configure.log" 2>&1 || die "libuv configure failed, see $BUILD/libuv-configure.log"
  cmake --build "$BUILD/libuv-build" > "$BUILD/libuv-build.log" 2>&1 \
    || die "libuv build failed, see $BUILD/libuv-build.log"
fi
echo "  libuv.a: $(du -h "$BUILD/libuv-build/libuv.a" | cut -f1)"

say "Generating headers CMake would otherwise produce"
SRC="$BUILD/lean4/src"
INC="$SRC/include/lean"
# The string fields in version.h.in are already wrapped in quotes by the template
# (`#define LEAN_PLATFORM_TARGET "@LEAN_PLATFORM_TARGET@"`), so substitutions here
# must be bare. Quoting them yields `""foo""`, which clang reads as a user-defined
# literal and rejects.
sed -e "s/@LEAN_VERSION_MAJOR@/${LEAN_VERSION%%.*}/" \
    -e "s/@LEAN_VERSION_MINOR@/$(echo "$LEAN_VERSION" | cut -d. -f2)/" \
    -e "s/@LEAN_VERSION_PATCH@/$(echo "$LEAN_VERSION" | cut -d. -f3)/" \
    -e 's/@LEAN_VERSION_IS_RELEASE@/1/' \
    -e "s|@LEAN_VERSION_STRING@|$LEAN_VERSION|" \
    -e 's|@LEAN_SPECIAL_VERSION_DESC@||' \
    -e 's|@LEAN_PLATFORM_TARGET@|aarch64-linux-android|' \
    -e 's|@LEAN_MANUAL_ROOT@|https://lean-lang.org/doc/|' \
    "$SRC/version.h.in" > "$INC/version.h"

# LEAN_MIMALLOC and LEAN_LAZY_RC are tested with #ifdef, so they must be absent
# rather than defined to 0. Defining them to 0 still pulls in <lean/mimalloc.h>.
cat > "$INC/config.h" <<'HDR'
#pragma once
#include <lean/version.h>
#define LEAN_IS_STAGE0 0
HDR

printf '#define LEAN_GITHASH "lean4-android"\n' > "$BUILD/githash.h"

say "Compiling the Lean runtime"
mkdir -p "$BUILD/obj"
OK=0; FAILED=""
for f in "$SRC"/runtime/*.cpp; do
  n="$(basename "$f" .cpp)"
  # openssl.cpp guards its OpenSSL includes with `#ifndef LEAN_EMSCRIPTEN`, so that
  # define compiles the same stub path the WebAssembly target uses and drops the
  # TLS dependency. It is scoped to this one file: applied globally, other sources
  # take their own Emscripten branches and look for <emscripten.h>.
  EXTRA=""
  [ "$n" = "openssl" ] && EXTRA="-DLEAN_EMSCRIPTEN"
  if "$CXX" -std=c++20 -O2 -fPIC -c "$f" \
      -I "$SRC" -I "$SRC/include" -I "$BUILD" -I "$BUILD/libuv/include" \
      $EXTRA \
      -o "$BUILD/obj/$n.o" 2>> "$BUILD/compile-errors.log"; then
    OK=$((OK+1))
  else
    FAILED="$FAILED $n"
  fi
done

TOTAL=$(ls "$SRC"/runtime/*.cpp | wc -l | tr -d ' ')
if [ -n "$FAILED" ]; then
  echo "  compiled $OK/$TOTAL"
  echo "  failed:$FAILED"
  die "see $BUILD/compile-errors.log"
fi

"$AR" rcs "$BUILD/libleanrt_android.a" "$BUILD"/obj/*.o

say "Done"
echo "  compiled $OK/$TOTAL runtime sources"
echo "  $BUILD/libleanrt_android.a ($(du -h "$BUILD/libleanrt_android.a" | cut -f1))"
echo "  $BUILD/libuv-build/libuv.a"
echo
echo "  This is the runtime only. Bootstrapping the compiler and stdlib is not"
echo "  done yet; see README.md."
