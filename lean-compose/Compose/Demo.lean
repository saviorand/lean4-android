/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Compose.Views
import Compose.Render

namespace Compose

/-- The screen the Android app renders. Written the way a Compose screen reads, but
the nesting rules are enforced by the type checker rather than by convention. -/
def demoScreen (count : Nat) : View .content :=
  scaffold
    (bar := some (topAppBar "Lean-authored UI"))
    (column (mod := { padding := 16 }) [
      text "This layout was authored in Lean." "titleMedium",
      spacer 12,
      text s!"count = {count}",
      spacer 12,
      row (mod := { padding := 4 }) [
        button "increment" "inc",
        spacer 8,
        button "reset" "reset"
      ],
      spacer 16,
      text "Nesting is checked at compile time: a button in the top-bar slot is a type error." "bodySmall"
    ])

@[export lean_demo_screen_json]
def demoScreenJson (count : UInt32) : String :=
  (demoScreen count.toNat).toJson

end Compose
