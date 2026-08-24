<a name="readme-top"></a>

<div align="center">
  <h3 align="center">lean4-android</h3>

  <p align="center">
    🤖 Lean 4, cross-compiled for Android 📱
    <br/>

   ![Written in Lean][language-shield]
   [![Apache 2.0 License][license-shield]][license-url]
   [![Contributors Welcome][contributors-shield]][contributors-url]

  </p>
</div>

## Overview

Lean publishes no Android build, and as far as we can tell nobody had tried: at the
time of writing `leanprover/lean4` has no issue mentioning Termux, Bionic,
`aarch64-linux-android` or seccomp.

This cross-compiles Lean 4 for `aarch64-linux-android` with the NDK. The runtime,
the standard library and the compiler all build, and Lean runs inside an Android app
process:

```
I LeanProbe: Lean runtime OK
I LeanProbe: array len=5 sum=70
I LeanProbe: string="lean on android" len=15
```

Verified on an Android 14 arm64-v8a device, against Lean v4.33.0 with NDK r29.

- [x] All 26 runtime sources compile against Bionic, unpatched
- [x] Full stage1: 4,982 modules, an ARM aarch64 `libleanshared.so` with 223,267 exported symbols
- [x] Runs in an APK
- [ ] Trimmed to a size an app could ship

## Getting Started

The only hard dependencies are the Android NDK, CMake, Ninja and git.

The runtime alone, which is quick and self-contained:

```bash
export ANDROID_NDK_HOME=/path/to/android-ndk
./scripts/build-runtime.sh
```

The whole toolchain, which is what an app links against:

```bash
elan toolchain install leanprover/lean4:v4.33.0
./scripts/build-stage1.sh
```

`build-stage1.sh` needs a **host** Lean of the same version: Lean is written in Lean,
and a cross-compiled compiler cannot run on the build machine. Expect ~5,000 modules
and about 10 GB of disk.

> [!NOTE]
> `build-stage1.sh` encodes a build that was carried out step by step and verified at
> each stage, but the script itself has not yet been run start to finish. If it fails,
> please open an issue: the fix is likely small.

## What it takes

Five host-versus-target leaks had to be closed. Two look like genuine upstream
portability bugs, both mistaking the platform the build runs on for the platform it
targets:

- **`LEAN_CC` never receives the toolchain's `--target`/`--sysroot`.** Lake invokes it
  directly rather than through `leanc.sh`, and Lean's CMake never folds in
  `CMAKE_C_FLAGS`, so every object fails on `sys/cdefs.h`.
- **Lake picks `libtool` from `System.Platform.isOSX`**, which reports the platform
  *Lake* was built for. A macOS host then hands BSD `libtool` a set of ELF objects.

The rest: libuv include paths, host `.dylib` versus `.so` naming, and a missing
`-fPIC`. [BOOTSTRAP.md](BOOTSTRAP.md) has the detail.

Running inside an app additionally needs
`android:allowNativeHeapPointerTagging="false"`. Android 11+ stores a tag in the top
byte of heap pointers and Lean's `lean_box` shifts values into it, so Bionic's
`free()` aborts. That flag is APK-only, which is why the same libraries cannot run
from `adb shell`.

## Roadmap

- [ ] **Size.** `libleanshared.so` is 161 MB stripped, 110 MB of it `.text` for the
      compiler and elaborator an app never calls. This is what stands between this
      and shipping anything.
- [ ] Upstream the two portability fixes as their own PRs
- [ ] A durable answer to pointer tagging; Google documents the manifest flag as a
      temporary escape hatch
- [ ] `lake` itself does not link for Android, which a self-hosting toolchain would need

## Related

- [lean-android-compose](https://github.com/saviorand/lean-android-compose) — a Compose app on top of this
- [lean-compose](https://github.com/saviorand/lean-compose) — authoring Compose UI in Lean

## Contributing

Contributions are welcome. This is early work in a place nobody has been, so issues
reporting what broke on your machine are as useful as patches.

## License

Distributed under the Apache 2.0 License. See [LICENSE](LICENSE) for more information.

<!-- MARKDOWN LINKS & IMAGES -->
[language-shield]: https://img.shields.io/badge/language-lean4-blueviolet
[license-shield]: https://img.shields.io/github/license/saviorand/lean4-android?logo=github
[license-url]: https://github.com/saviorand/lean4-android/blob/main/LICENSE
[contributors-shield]: https://img.shields.io/badge/contributors-welcome!-blue
[contributors-url]: https://github.com/saviorand/lean4-android#contributing
