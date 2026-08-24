package com.leanandroid.compose

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.json.JSONArray
import org.json.JSONObject

/**
 * Renders a view tree authored in Lean.
 *
 * The tree arrives as JSON from [Lean.screenJson]. Lean's type checker has already
 * ruled out the invalid nestings (a button where a top bar belongs, say), so this
 * side only has to map node kinds onto Composables.
 */
@Composable
fun LeanView(node: JSONObject, onAction: (String) -> Unit) {
    when (node.getString("t")) {
        "scaffold" -> {
            val bar = node.optJSONObject("bar")
            Scaffold(
                topBar = {
                    if (bar != null) LeanView(bar, onAction)
                }
            ) { padding ->
                Box(Modifier.padding(padding)) {
                    LeanView(node.getJSONObject("body"), onAction)
                }
            }
        }

        "topAppBar" -> @OptIn(ExperimentalMaterial3Api::class) TopAppBar(
            title = { Text(node.getString("title")) }
        )

        "column" -> Column(node.modifier()) {
            node.children().forEach { LeanView(it, onAction) }
        }

        "row" -> Row(node.modifier()) {
            node.children().forEach { LeanView(it, onAction) }
        }

        "text" -> Text(
            text = node.getString("content"),
            style = when (node.getString("style")) {
                "titleMedium" -> MaterialTheme.typography.titleMedium
                "bodySmall" -> MaterialTheme.typography.bodySmall
                else -> MaterialTheme.typography.bodyMedium
            }
        )

        "button" -> Button(onClick = { onAction(node.getString("action")) }) {
            Text(node.getString("label"))
        }

        "spacer" -> Spacer(Modifier.size(node.getInt("size").dp))

        // An unknown node means Lean and Kotlin have drifted apart; say so on screen
        // rather than rendering nothing and leaving a blank region to explain.
        else -> Text("unhandled node: ${node.getString("t")}")
    }
}

private fun JSONObject.children(): List<JSONObject> {
    val arr: JSONArray = optJSONArray("children") ?: return emptyList()
    return (0 until arr.length()).map { arr.getJSONObject(it) }
}

private fun JSONObject.modifier(): Modifier {
    val m = optJSONObject("mod") ?: return Modifier
    var mod: Modifier = Modifier
    when (val w = m.opt("width")) {
        "fill" -> mod = mod.fillMaxWidth()
        is Int -> mod = mod.width(w.dp)
    }
    when (val h = m.opt("height")) {
        "fill" -> mod = mod.fillMaxHeight()
        is Int -> mod = mod.height(h.dp)
    }
    val padding = m.optInt("padding", 0)
    if (padding > 0) mod = mod.padding(padding.dp)
    return mod
}

/**
 * The Lean-authored screen bundled with the app.
 *
 * Reads the tree Lean rendered at build time. Once `lean-compose` is cross-compiled
 * into `libleanshared.so`, this becomes a JNI call to `lean_demo_screen_json`
 * instead, and the layout can then depend on runtime state.
 */
@Composable
fun LeanAuthoredScreen() {
    val ctx = androidx.compose.ui.platform.LocalContext.current
    val tree = androidx.compose.runtime.remember {
        runCatching {
            JSONObject(ctx.assets.open("screen.json").bufferedReader().use { it.readText() })
        }.getOrNull()
    }
    if (tree == null) {
        Text("screen.json missing")
    } else {
        LeanView(tree) { action ->
            android.util.Log.i("LeanView", "action: $action")
        }
    }
}
