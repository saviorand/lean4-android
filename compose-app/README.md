# compose-app

A Jetpack Compose app that calls Lean over JNI. Verified on a HiBreak
(Android 14, arm64-v8a).

The UI is ordinary Compose; everything below the JNI boundary runs in Lean, using
its allocator, its object model and its arbitrary-precision `Nat`.

## What it does

- `Lean.version()` reports the runtime's own version and platform target.
- `Lean.factorial(n)` multiplies through Lean's `Nat`, so past 20! it is running
  Lean's bignum path rather than 64-bit arithmetic. The result comes back as a
  string via `Nat.reprFast`.
- `Lean.sumTo(n)` builds a genuine Lean linked list with `lean_alloc_ctor` and walks
  it, exercising the allocator and object layout rather than a C loop.

## Building

Needs `scripts/build-stage1.sh` to have produced `libleanshared.so`, then:

```
cp <build>/stage1/lib/lean/libleanshared.so app/src/main/jniLibs/arm64-v8a/
cp <ndk>/.../libc++_shared.so               app/src/main/jniLibs/arm64-v8a/
cp <build>/libuv-build/libuv.so             app/src/main/jniLibs/arm64-v8a/
<ndk>/bin/aarch64-linux-android34-clang -shared -fPIC \
  -o app/src/main/jniLibs/arm64-v8a/libleanbridge.so \
  app/src/main/cpp/leanbridge.c \
  -I <build>/stage1/include -L <build>/stage1/lib/lean -lleanshared -Wl,--no-undefined

ANDROID_HOME=~/Library/Android/sdk gradle assembleDebug
```

The `.so` files are gitignored; the APK is 64 MB with Gradle's compression, from
162 MB of raw libraries.

## Notes

**The manifest flag is still required.** `android:allowNativeHeapPointerTagging="false"`,
for the reason in [../android-probe/README.md](../android-probe/README.md).

**`Lean.init()` must not run on the main thread.** Mapping ~160 MB and running
Lean's module initialisers takes minutes on first launch, so the UI shows a
progress indicator and does the work on `Dispatchers.Default`.

**Two things that cost time:**

- `@style/Theme.Material3.DayNight.NoActionBar` is not an XML resource. Compose
  themes in code, so the platform theme just needs to stay out of the way.
- `lean_nat_to_string` does not exist. `Nat` to `String` is `l_Nat_reprFast`,
  declared `extern`; it consumes its argument.
