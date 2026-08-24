# Bootstrapping the compiler and stdlib

Notes from a partial cross-build of stage1. Not finished: this records what works,
the three cross-compilation gaps found so far, and where it currently stops.

## Result so far

Lean's standard library **does** cross-compile to Android. 2,324 `.olean` files
build, and generated Lean code compiles to real Android objects:

```
$ file stage1/lib/temp/Init/BinderNameHint.c.o.export
ELF 64-bit LSB relocatable, ARM aarch64
```

The build does not yet complete; see [Where it stops](#where-it-stops).

## Approach

Lean is written in Lean, so building the stdlib needs a working `lean`. A
cross-compiled stage0 cannot run on the build host, so a **host** stage0 drives a
**cross-compiled** stage1:

```
-DSTAGE1_PREV_STAGE=~/.elan/toolchains/leanprover--lean4---v4.33.0
```

That skips building stage0 entirely (root `CMakeLists.txt`, `if(NOT STAGE1_PREV_STAGE)`).
Stage1 then takes the `else()` branch of `if(STAGE GREATER 1)`, so it builds the
runtime from source rather than copying the host's `.a` files, which is what makes
this viable.

**Dependency overrides need the `STAGE1_` prefix.** Unprefixed `-D` reaches only the
outer project; stage1 re-runs `find_package` and picks up host libraries. Without
the prefix, `pkg-config` found `/opt/homebrew/Cellar/libuv` for an Android build.

OpenSSL **is** required here, unlike the runtime-only build:

```
./Configure android-arm64 -D__ANDROID_API__=34 no-shared no-tests
```

with the NDK `bin` on `PATH`. Produces `elf64-littleaarch64`.

## The three gaps

Each is the same shape: a host tool or flag leaking into the cross-build.

### 1. `LEAN_CC` drops the toolchain's target flags

Lake compiles generated C by invoking `$LEAN_CC` **directly, not through
`leanc.sh`**. `src/stdlib.make.in` sets it from `CMAKE_C_COMPILER` alone:

```make
ifeq "${USE_LAKE}" "ON"
  export LEAN_CC=${CMAKE_C_COMPILER}
```

`src/CMakeLists.txt` builds `LEANC_EXTRA_CC_FLAGS` from hardcoded flags and never
reads `CMAKE_C_FLAGS`, so the NDK toolchain file's `--target` and `--sysroot` never
reach it. Bare clang then defaults to the host and every object compilation fails
with `sys/cdefs.h not found`.

Setting `-DCMAKE_C_COMPILER` does not help: the NDK toolchain file runs later and
overwrites it.

`LEAN_CC` takes a single executable path, so flags cannot be appended. The fix is a
wrapper script that execs clang with the target flags, plus a one-line change to
`src/stdlib.make.in` to let the build point at one:

```make
ifneq "${LEAN_CC_EXE}" ""
  export LEAN_CC=${LEAN_CC_EXE}
else ifeq "${USE_LAKE}" "ON"
  ...
```

With `-DSTAGE1_LEAN_CC_EXE=<wrapper>`, `sys/cdefs.h` failures go to zero.

This looks like a genuine upstream portability gap, and a narrow enough one to be
worth offering as its own PR.

### 2. libuv headers are not on the stdlib include path

Generated code includes `uv.h`, but stage1's include directory holds only `lean/`.
Adding `-I <libuv>/include` to the wrapper took failures from 1,921 to 403.

### 3. Host `libtool` archives Android objects

The remaining failure. Objects are produced correctly as ARM aarch64, then the
**host** `libtool` is used to archive them:

```
libtool: warning: not a mach-o '.../Init/Internal/Order/Basic.c.o.export'
```

macOS archiving tools on Android objects. Needs `llvm-ar` from the NDK instead;
`CMAKE_AR`/`CMAKE_RANLIB` are not reaching this step.

## Where it stops

At gap 3. 2,324 oleans and 47 verified Android objects exist, but nothing is
archived or linked, so there is no runnable artifact yet.

## Reproducing

Not scripted yet, deliberately: two of the three fixes are workarounds rather than
something to commit to. `scripts/build-runtime.sh` covers the runtime, which is
reproducible and complete.
