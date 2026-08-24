<a name="readme-top"></a>

<div align="center">
  <h3 align="center">lean4-android</h3>

  <p align="center">
    Lean 4, cross-compiled for Android
    <br/>

   ![Written in Lean][language-shield]
   [![Apache 2.0 License][license-shield]][license-url]
   [![Contributors Welcome][contributors-shield]][contributors-url]

  </p>
</div>

## Overview

there's no Android build of Lean, and as far as i can tell nobody had tried:
`leanprover/lean4` has no issue mentioning Termux, Bionic, `aarch64-linux-android`
or seccomp.

this cross-compiles Lean 4 for `aarch64-linux-android` with the NDK. the runtime,
the stdlib and the compiler all build, and Lean runs inside an Android app process:

```
I LeanProbe: Lean runtime OK
I LeanProbe: array len=5 sum=70
I LeanProbe: string="lean on android" len=15
```

tested on an Android 14 arm64-v8a device, against Lean v4.33.0 with NDK r29.

- [x] all 26 runtime sources compile against Bionic, unpatched
- [x] full stage1: 4,982 modules, an ARM aarch64 `libleanshared.so` with 223,267 exported symbols
- [x] runs in an APK
- [ ] small enough for an app to actually ship

## Getting Started

you need the Android NDK, CMake, Ninja and git.

the runtime on its own is quick and self-contained:

```bash
export ANDROID_NDK_HOME=/path/to/android-ndk
./scripts/build-runtime.sh
```

the whole toolchain, which is what an app links against:

```bash
elan toolchain install leanprover/lean4:v4.33.0
./scripts/build-stage1.sh
```

`build-stage1.sh` needs a **host** Lean of the same version. Lean is written in Lean,
so a cross-compiled compiler can't run on the build machine and something has to
drive it. expect ~5,000 modules and about 10 GB of disk.

> [!NOTE]
> i built this step by step and checked each stage, but haven't run the script
> start to finish yet. if it breaks please open an issue, the fix is probably small.

## What it takes

five host-versus-target leaks had to be closed. two of them look like real upstream
bugs, both mistaking the platform the build runs on for the one it targets:

- **`LEAN_CC` never gets the toolchain's `--target`/`--sysroot`.** Lake calls it
  directly instead of going through `leanc.sh`, and Lean's CMake never folds in
  `CMAKE_C_FLAGS`, so every object fails on `sys/cdefs.h`.
- **Lake picks `libtool` from `System.Platform.isOSX`**, which is the platform *Lake*
  was built for, not the target. on a macOS host that hands BSD `libtool` a pile of
  ELF objects.

the rest were libuv include paths, host `.dylib` vs `.so` naming, and a missing
`-fPIC`. [BOOTSTRAP.md](BOOTSTRAP.md) has the detail.

running inside an app also needs `android:allowNativeHeapPointerTagging="false"`.
Android 11+ puts a tag in the top byte of heap pointers and Lean's `lean_box` shifts
values into it, so Bionic's `free()` aborts. that flag is APK-only, which is why the
same libraries can't be made to work from `adb shell`.

## Roadmap

- [ ] **size.** `libleanshared.so` is 161 MB stripped, 110 MB of it `.text` for the
      compiler and elaborator an app never calls. this is the thing standing between
      this and shipping anything
- [ ] send the two portability fixes upstream as separate PRs
- [ ] something better than the pointer tagging flag, which Google documents as a
      temporary escape hatch
- [ ] `lake` itself doesn't link for Android, which a self-hosting toolchain would need

## Related

- [lean-android-compose](https://github.com/saviorand/lean-android-compose) — a Compose app on top of this
- [lean-compose](https://github.com/saviorand/lean-compose) — authoring Compose UI in Lean

## Contributing

contributions welcome. this is early work somewhere nobody's been, so an issue
saying what broke on your machine is as useful as a patch.

## License

Distributed under the Apache 2.0 License. See [LICENSE](LICENSE) for more information.

<!-- MARKDOWN LINKS & IMAGES -->
[language-shield]: https://img.shields.io/badge/language-lean4-blueviolet
[license-shield]: https://img.shields.io/github/license/saviorand/lean4-android?logo=github
[license-url]: https://github.com/saviorand/lean4-android/blob/main/LICENSE
[contributors-shield]: https://img.shields.io/badge/contributors-welcome!-blue
[contributors-url]: https://github.com/saviorand/lean4-android#contributing
