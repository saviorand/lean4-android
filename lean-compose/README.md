# lean-compose

A typed DSL for authoring Compose UI in Lean, in the manner of
[lean-html](https://github.com/paulbutcher/lean-html).

The idea is the same: index the view type by where it is allowed to appear, so that
invalid nesting is a type error rather than a layout bug noticed on a screen.

```lean
def demoScreen (count : Nat) : View .content :=
  scaffold
    (bar := some (topAppBar "Lean-authored UI"))
    (column (mod := { padding := 16 }) [
      text "This layout was authored in Lean." "titleMedium",
      spacer 12,
      text s!"count = {count}",
      row [ button "increment" "inc", spacer 8, button "reset" "reset" ]
    ])
```

Putting a button where the top bar belongs does not compile:

```
error: Application type mismatch: The argument
  button "no" "x"
has type
  View Category.content
```

Compose itself makes no such distinction: any `@Composable` nests inside any other,
and a slot expecting a bar will accept a button and lay it out wrongly.

## What is modelled

`Category` carries the distinctions that matter at the boundary: `.content` for
anything that goes in a column, row or box; `.topBar` for the one thing a `Scaffold`
accepts as a bar; `.navItem` for navigation children. Sibling *ordering* is
deliberately not modelled, the same choice lean-html makes for HTML5.

`View`'s constructor is private, so the only way to obtain one is through the
constructors in `Compose/Views.lean`, which is what keeps the index meaningful.

## Rendering

`View.toJson` emits a tree that `compose-app`'s `LeanView.kt` interprets into real
Composables. JSON rather than generated Kotlin, so the UI can change without
recompiling the app.

`toJson` and `childrenJson` are mutually recursive rather than using a nested
`List.map`, because a closure hides the recursive call from the structural
termination checker. Nothing here is `partial` and nothing can panic.

## Tests

Structural facts are theorems (`bar_is_topBar`, `coe_string_is_text`,
`nesting_preserved`, `scaffold_no_bar`). The string-level facts are runtime checks
instead: `escape` and `toJson` are built from `String.foldl` and append, neither of
which reduces definitionally, `simp` on a whole document exhausts the heartbeat
limit, and `native_decide` would close them only by adding a trusted axiom for what
is really an output-format check.

```
lake build && lake test
```

## Status

The DSL, the renderer and the Kotlin interpreter all work, and the demo screen
renders on device.

**The JSON is currently generated at build time**, not by Lean running on the phone.
`demoScreenJson` is already marked `@[export lean_demo_screen_json]`, so the
remaining step is cross-compiling this library into `libleanshared.so` and calling
it over JNI, at which point the layout can depend on runtime state.
