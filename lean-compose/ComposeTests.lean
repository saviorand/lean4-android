/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Compose

open Compose

namespace ComposeTests

/-- Only a `topAppBar` inhabits `.topBar`. The real check is that this file compiles
at all: giving `scaffold` a `button` for its bar is a type error, not a test
failure. -/
theorem bar_is_topBar : (topAppBar "t").repr = .topAppBar "t" := rfl

/-- A string literal in a child list is a text node, so the `Coe` does what a reader
would assume from the syntax. -/
theorem coe_string_is_text : (column ["hi"]).repr = (column [text "hi"]).repr := rfl

/-- Nesting is preserved rather than flattened. -/
theorem nesting_preserved :
    (column [row [text "x"]]).repr =
      .column {} [.row {} [.text "x" "body"]] := rfl

/-- A scaffold without a bar carries `none`, rather than inventing one. -/
theorem scaffold_no_bar : (scaffold (text "x")).repr = .scaffold none (.text "x" "body") := rfl

/-- Rendering is a function of the tree, so two routes to the same tree render
identically. This is what lets the Kotlin side treat the JSON as canonical. -/
theorem render_respects_structure (a b : Repr') (h : a = b) : a.toJson = b.toJson := by
  rw [h]

-- The string-level facts below are checked by running them rather than by proof:
-- `escape` and `toJson` are defined by `String.foldl` and string append, neither of
-- which reduces definitionally, and `simp` on a whole rendered document exhausts
-- the heartbeat limit. `native_decide` would close them but adds a trusted axiom
-- for what is really an output-format check, so these run as assertions instead.

private def check (name expected actual : String) : IO Bool := do
  if expected == actual then
    pure true
  else
    IO.eprintln s!"{name}:\n  expected {expected}\n  actual   {actual}"
    pure false

def escapeChecks : IO Bool := do
  let mut ok := true
  ok := (← check "plain text untouched" "hello world" (escape "hello world")) && ok
  ok := (← check "quote escaped" "a\\\"b" (escape "a\"b")) && ok
  ok := (← check "backslash escaped" "a\\\\b" (escape "a\\b")) && ok
  ok := (← check "newline escaped" "a\\nb" (escape "a\nb")) && ok
  -- A raw control character would produce JSON no parser accepts.
  ok := (← check "control dropped" "ab" (escape "a\x01b")) && ok
  pure ok

def renderChecks : IO Bool := do
  let mut ok := true
  ok := (← check "empty children render as []"
    "{\"t\":\"column\",\"mod\":{\"width\":\"wrap\",\"height\":\"wrap\",\"padding\":0,\"weight\":null},\"children\":[]}"
    (column []).toJson) && ok
  -- Trailing commas are the most likely way to break a parser and the least likely
  -- to be spotted by eye.
  ok := (← check "siblings comma-separated, no trailing comma"
    ("{\"t\":\"row\",\"mod\":{\"width\":\"wrap\",\"height\":\"wrap\",\"padding\":0,\"weight\":null},\"children\":["
      ++ "{\"t\":\"text\",\"content\":\"a\",\"style\":\"body\"},"
      ++ "{\"t\":\"text\",\"content\":\"b\",\"style\":\"body\"}]}")
    (row [text "a", text "b"]).toJson) && ok
  pure ok

end ComposeTests

def main : IO Unit := do
  let ok := (← ComposeTests.escapeChecks) && (← ComposeTests.renderChecks)
  if ok then
    IO.println "lean-compose: ok"
  else
    throw (IO.userError "lean-compose: checks failed")
