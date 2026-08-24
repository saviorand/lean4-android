/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Compose.Core

namespace Compose

/-- Lets a string literal stand in for `text`, so a column of labels reads as a
list of strings. -/
instance : Coe String (View .content) where
  coe s := View.ofRepr (.text s "body")

def text (content : String) (style : String := "body") : View .content :=
  View.ofRepr (.text content style)

def button (label : String) (action : String) : View .content :=
  View.ofRepr (.button label action)

def spacer (size : Nat) : View .content :=
  View.ofRepr (.spacer size)

def column (children : List (View .content)) (mod : Modifier := {}) : View .content :=
  View.ofRepr (.column mod (children.map View.repr))

def row (children : List (View .content)) (mod : Modifier := {}) : View .content :=
  View.ofRepr (.row mod (children.map View.repr))

/-- Only a `topAppBar` inhabits `.topBar`, so `scaffold` cannot be handed a button
where a bar belongs. -/
def topAppBar (title : String) : View .topBar :=
  View.ofRepr (.topAppBar title)

def navigationBarItem (label : String) (action : String) : View .navItem :=
  View.ofRepr (.navigationBarItem label action)

def scaffold (body : View .content) (bar : Option (View .topBar) := none) : View .content :=
  View.ofRepr (.scaffold (bar.map View.repr) body.repr)

end Compose
