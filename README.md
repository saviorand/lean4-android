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

lean4-android cross-compiles Lean 4 for `aarch64-linux-android` with the NDK. The
runtime, the standard library and the compiler all build, and the result runs inside
an Android app process.

Tested on an Android 14 arm64-v8a device, against Lean v4.33.0 with NDK r29.

- [x] All 26 runtime sources compile against Bionic, unpatched
- [x] Full stage1 build: 4,982 modules, producing an ARM aarch64 `libleanshared.so`
      with 223,267 exported symbols
- [x] Runs in an APK, with a minimal probe app to demonstrate it
- [ ] Small enough for an app to ship

## Getting Started

The hard dependencies are the Android NDK, CMake, Ninja and git.

To build the runtime on its own, which is quick and self-contained:

```bash
export ANDROID_NDK_HOME=/path/to/android-ndk
./scripts/build-runtime.sh
```

This produces `libleanrt_android.a`, about 1.3 MB.

To build the whole toolchain, which is what an application links against:

```bash
elan toolchain install leanprover/lean4:v4.33.0
./scripts/build-stage1.sh
```

Lean is written in Lean, so a cross-compiled compiler cannot run on the build
machine. `build-stage1.sh` therefore needs a host Lean of the same version to drive
the build. Expect roughly 5,000 modules and 10 GB of disk.

> [!NOTE]
> The stage1 build was carried out step by step and verified at each stage, but the
> script has not yet been run start to finish. If it fails, please open an issue.

## Portability findings

Five host-versus-target leaks had to be closed to get a working build. Two of them
look like upstream bugs rather than anything Android-specific, both mistaking the
platform the build runs on for the platform it targets:

- **`LEAN_CC` does not receive the toolchain's `--target` and `--sysroot`.** Lake
  invokes it directly rather than through `leanc.sh`, and `src/CMakeLists.txt` never
  folds in `CMAKE_C_FLAGS`, so every object compilation fails on `sys/cdefs.h`.
- **Lake selects `libtool` from `System.Platform.isOSX`**, which reports the platform
  Lake itself was built for. A macOS host then hands BSD `libtool` a set of ELF
  objects it cannot archive.

The remaining three were libuv include paths, host `.dylib` versus `.so` naming, and
a missing `-fPIC`. [BOOTSTRAP.md](BOOTSTRAP.md) covers all five in detail.

Running inside an application additionally requires
`android:allowNativeHeapPointerTagging="false"`. Android 11 and later store a tag in
the top byte of heap pointers, and Lean's `lean_box` shifts values into that byte, so
Bionic's `free()` aborts. The flag is APK-only, which is why the same libraries
cannot be run from `adb shell`.

## Roadmap

- [ ] Reduce size. `libleanshared.so` is 161 MB stripped, 110 MB of which is `.text`
      for the compiler and elaborator that an application never calls
- [ ] Submit the two portability fixes upstream as separate PRs
- [ ] Replace the pointer tagging flag, which Google documents as a temporary escape
      hatch
- [ ] Link `lake` for Android, which a self-hosting toolchain would need

## Related

- [lean-android-compose](https://github.com/saviorand/lean-android-compose) — a Compose app built on this
- [lean-compose](https://github.com/saviorand/lean-compose) — authoring Compose UI in Lean

## Contributing

Contributions are welcome. This is early work, so an issue describing what broke on
your machine is as useful as a patch.

## License

Distributed under the Apache 2.0 License. See [LICENSE](LICENSE) for more information.

<!-- MARKDOWN LINKS & IMAGES -->
[language-shield]: https://img.shields.io/badge/language-lean4-blueviolet
[license-shield]: https://img.shields.io/github/license/saviorand/lean4-android?logo=github
[license-url]: https://github.com/saviorand/lean4-android/blob/main/LICENSE
[contributors-shield]: https://img.shields.io/badge/contributors-welcome!-blue
[contributors-url]: https://github.com/saviorand/lean4-android#contributing
