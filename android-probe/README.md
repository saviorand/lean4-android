# android-probe

A minimal APK that initialises the Lean runtime and evaluates something, to prove
Lean works inside an Android app process.

## Result

On a HiBreak (Android 14, arm64-v8a):

```
I LeanProbe: Lean runtime OK
I LeanProbe: array len=5 sum=70
I LeanProbe: string="lean on android" len=15
```

`sum=70` is `0+7+14+21+28`, computed through `lean_box`/`lean_unbox`. The array goes
through Lean's allocator and the string through Lean's own representation, so the
object model, the allocator and the boxing path all work.

## The one thing that makes it work

```xml
<application android:allowNativeHeapPointerTagging="false">
```

Without it the process aborts:

```
Pointer tag for 0x773f2394b0 was truncated
Fatal signal 6 (SIGABRT) in tid ... (lean)
```

Android 11+ stores a tag in the top byte of every heap pointer. Lean's `lean_box` is
`(n << 1) | 1`, which shifts values into that byte; Bionic's `free()` then sees a
stripped tag and aborts. The manifest flag is the only supported way to turn this
off, which is why the same binary cannot be made to run from `adb shell`: there is
no equivalent for a bare executable. `LD_POINTER_TAGGING=0`,
`MALLOC_DISABLE_TAGGING=1` and a hand-built `.note.android.memtag` section were all
tried and none work; that note controls MTE, a different mechanism.

llama.cpp and Kotlin hit the same abort under Termux, so this is a known class of
failure rather than anything specific to Lean.

Google documents the flag as a temporary escape hatch. The durable fix is Lean not
storing data in the top byte on Android, which is upstream work.

## Building

Needs the SDK (build-tools 34, platform 34) as well as the NDK, and a completed
`scripts/build-stage1.sh`. The steps are aapt2 compile/link, javac, d8, zip the
native libs and dex in, zipalign, apksigner. Not scripted yet.

## Size

162 MB, essentially all `libleanshared.so`. `.text` alone is 110 MB: the whole Lean
compiler and elaborator, almost none of which an app needs. Trimming this is the
main open problem before anything ships.
