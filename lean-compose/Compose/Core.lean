/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/

namespace Compose

/-- Where a view is allowed to appear.

Compose itself is untyped about this: any `@Composable` can nest inside any other,
and a `Scaffold` slot that wants a top bar will happily accept a `Button` and lay
it out wrongly. The categories below recover the distinctions that actually matter
at the boundary we render across, so a slot expecting a bar cannot be handed a
general widget. What is deliberately not modelled is ordering among siblings. -/
inductive Category where
  | /-- Anything that can appear in a column, row, or box. -/
    content
  | /-- Valid only in `Scaffold`'s `topBar` slot. -/
    topBar
  | /-- Valid only as a `NavigationBar` child. -/
    navItem
  deriving DecidableEq, Repr

/-- How a child is measured against its siblings. -/
inductive Size where
  | wrap
  | fill
  | dp (value : Nat)
  deriving DecidableEq, Repr

/-- Layout and appearance applied to a single view.

A record rather than Compose's chained `Modifier`, because the chain's order is
mostly irrelevant to the properties here and a record makes the rendered output a
function of the fields rather than of a call sequence. -/
structure Modifier where
  width : Size := .wrap
  height : Size := .wrap
  padding : Nat := 0
  weight : Option Nat := none
  deriving DecidableEq, Repr

/-- The internal tree.

Exposed rather than `private` so that proofs can do induction on it. Callers should
build views with the constructors in `Compose/Views.lean`, which is what keeps the
category index meaningful. -/
inductive Repr' where
  | text (content : String) (style : String)
  | button (label : String) (action : String)
  | column (mod : Modifier) (children : List Repr')
  | row (mod : Modifier) (children : List Repr')
  | spacer (size : Nat)
  | topAppBar (title : String)
  | navigationBarItem (label : String) (action : String)
  | scaffold (bar : Option Repr') (body : Repr')
  deriving Repr

/-- A view, indexed by where it may appear.

`mk` is private: the only way to obtain a `View` is through the constructors, so a
view carrying the wrong category cannot be fabricated. -/
structure View (cat : Category) where
  private mk ::
  repr : Repr'

namespace View

/-- Wraps a tree in a category. Not for general use: every caller outside this
library should go through the constructors in `Compose/Views.lean`, which is what
makes the category index mean anything. -/
def ofRepr (r : Repr') : View cat := ⟨r⟩

end View
end Compose
