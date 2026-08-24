# Bootstrapping the compiler and stdlib

The full stage1 cross-build works: 4,982 modules, 0 failures. This records the
five gaps that had to be closed, all of them the same shape, plus what remains.

## Result

```
$ file stage1/lib/lean/libleanshared.so
ELF 64-bit LSB shared object, ARM aarch64, dynamically linked

$ llvm-readelf -d libleanshared.so | grep NEEDED
  libc++_shared.so  libuv.so  libm.so  libdl.so  libc.so

$ file stage1/bin/lean
ELF 64-bit LSB pie executable, ARM aarch64, interpreter /system/bin/linker64
```

Bionic's unversioned `libc.so`/`libm.so`/`libdl.so`, not glibc's `libc.so.6`.
223,267 exported symbols. `libInit.a` 28 MB, `libStd.a` 33 MB, `libLean.a` 328 MB.

Reproduced by `scripts/build-stage1.sh`.

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

## The five gaps

Each is the same shape: a host tool, flag or assumption leaking into the cross-build.

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

`Lake/Build/Library.lean` selects the archiver like this:

```lean
if bootstrap then
  if System.Platform.isOSX then
    proc {cmd := "libtool", args := #["-static", "-o", ...
```

`System.Platform.isOSX` is the platform **Lake itself** was built for, not the
target. A macOS host Lake therefore hands BSD `libtool` a set of ELF objects:

```
libtool: warning: not a mach-o '.../Init/Internal/Order/Basic.c.o.export'
```

`LEAN_AR` is passed correctly but only consulted on the non-macOS branches. Worked
around with a shim translating `-static -o OUT -filelist F` into `llvm-ar rcs OUT @F`.

Like gap 1, this is a real upstream bug: it mistakes the build host for the target.

### 4. Host ships `.dylib`, build wants `.so`

The build loads `<host-toolchain>/lib/lean/libLake_shared.so` as a plugin, but elan
ships `.dylib` on macOS. Additive symlinks in the host toolchain; nothing is
overwritten and they are trivially removable.

### 5. `-fPIC`

```
ld.lld: error: relocation R_AARCH64_ADD_ABS_LO12_NC cannot be used against
symbol 'l_Lean_IR_ToIR_lowerLet___lam__0___boxed'; recompile with -fPIC
```

The stdlib objects end up in a shared library and Android rejects text relocations.
Added to the `LEAN_CC` wrapper.

## What still fails

`lake` does not link (undefined `Lake_*` symbols). It is a host-side build tool, so
Android does not need it, but a self-hosting toolchain would.

## Not verified

**Nothing has run on a device.** The artifacts have the right architecture, the
right interpreter and the right Bionic dependencies, but that is a static claim.

## Upstream

Gaps 1 and 3 are narrow, genuine portability bugs, each worth its own PR
independent of anyone adopting Android as a platform.
