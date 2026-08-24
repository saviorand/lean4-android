/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Compose.Core

namespace Compose

/-- Escapes the characters JSON forbids in a string body.

Control characters below 0x20 have to go somewhere; they are dropped rather than
escaped, since no view text should contain them and `\uXXXX` would need more
machinery than the rest of this renderer. -/
def escape (s : String) : String :=
  s.foldl (init := "") fun acc c =>
    match c with
    | '"'  => acc ++ "\\\""
    | '\\' => acc ++ "\\\\"
    | '\n' => acc ++ "\\n"
    | '\r' => acc ++ "\\r"
    | '\t' => acc ++ "\\t"
    | c    => if c.val < 0x20 then acc else acc.push c

private def sizeJson : Size → String
  | .wrap => "\"wrap\""
  | .fill => "\"fill\""
  | .dp n => toString n

private def modJson (m : Modifier) : String :=
  let weight := match m.weight with
    | none => "null"
    | some w => toString w
  "{\"width\":" ++ sizeJson m.width ++
  ",\"height\":" ++ sizeJson m.height ++
  ",\"padding\":" ++ toString m.padding ++
  ",\"weight\":" ++ weight ++ "}"

-- `toJson` and `childrenJson` are mutually recursive rather than using a nested
-- `List.map`: a closure hides the recursive call from the structural checker,
-- whereas this pair is accepted directly and stays total.
mutual

/-- Renders the tree as JSON for the Kotlin side to interpret. -/
def Repr'.toJson : Repr' → String
  | .text content style =>
    "{\"t\":\"text\",\"content\":\"" ++ escape content ++ "\",\"style\":\"" ++ escape style ++ "\"}"
  | .button label action =>
    "{\"t\":\"button\",\"label\":\"" ++ escape label ++ "\",\"action\":\"" ++ escape action ++ "\"}"
  | .spacer size =>
    "{\"t\":\"spacer\",\"size\":" ++ toString size ++ "}"
  | .topAppBar title =>
    "{\"t\":\"topAppBar\",\"title\":\"" ++ escape title ++ "\"}"
  | .navigationBarItem label action =>
    "{\"t\":\"navItem\",\"label\":\"" ++ escape label ++ "\",\"action\":\"" ++ escape action ++ "\"}"
  | .column mod children =>
    "{\"t\":\"column\",\"mod\":" ++ modJson mod ++
      ",\"children\":[" ++ Repr'.childrenJson children ++ "]}"
  | .row mod children =>
    "{\"t\":\"row\",\"mod\":" ++ modJson mod ++
      ",\"children\":[" ++ Repr'.childrenJson children ++ "]}"
  | .scaffold bar body =>
    let barJson := match bar with
      | none => "null"
      | some b => b.toJson
    "{\"t\":\"scaffold\",\"bar\":" ++ barJson ++ ",\"body\":" ++ body.toJson ++ "}"

/-- Comma-separated siblings. Separate from `toJson` so the recursion is structural. -/
def Repr'.childrenJson : List Repr' → String
  | [] => ""
  | [c] => c.toJson
  | c :: rest => c.toJson ++ "," ++ Repr'.childrenJson rest

end

def View.toJson (v : View cat) : String := v.repr.toJson

end Compose
