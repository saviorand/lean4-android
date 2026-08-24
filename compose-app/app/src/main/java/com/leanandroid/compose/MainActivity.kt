package com.leanandroid.compose

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MaterialTheme { Screen() } }
    }
}

@Composable
private fun Screen() {
    val scope = rememberCoroutineScope()
    var ready by remember { mutableStateOf(false) }
    var banner by remember { mutableStateOf("starting the Lean runtime…") }
    var n by remember { mutableStateOf(20) }
    var factorial by remember { mutableStateOf("") }
    var listSum by remember { mutableStateOf("") }

    LaunchedEffect(Unit) {
        // The first call maps ~160 MB and runs Lean's module initialisers, so it
        // must not touch the main thread.
        val ok = withContext(Dispatchers.Default) { Lean.init() }
        banner = if (ok) withContext(Dispatchers.Default) { Lean.version() }
                 else "Lean failed to initialise"
        ready = ok
    }

    Column(
        Modifier.fillMaxSize().padding(24.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text("Lean on Android", style = MaterialTheme.typography.headlineSmall)
        Text(banner, style = MaterialTheme.typography.bodyMedium)

        if (!ready) {
            LinearProgressIndicator(Modifier.fillMaxWidth())
            Text(
                "First launch maps a ~160 MB shared library; this takes a while.",
                style = MaterialTheme.typography.bodySmall
            )
            return@Column
        }

        HorizontalDivider()

        // A screen whose structure was authored in Lean and checked by its type
        // system; see ../../lean-compose. The JSON is generated at build time for
        // now, since the Lean library still has to be cross-compiled into
        // libleanshared.so to be callable over JNI.
        LeanAuthoredScreen()

        HorizontalDivider()

        Text("n = $n", style = MaterialTheme.typography.titleMedium)
        Slider(
            value = n.toFloat(),
            onValueChange = { n = it.toInt() },
            valueRange = 1f..500f
        )

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(onClick = {
                scope.launch {
                    factorial = withContext(Dispatchers.Default) { Lean.factorial(n) }
                }
            }) { Text("n! in Lean") }

            OutlinedButton(onClick = {
                scope.launch {
                    listSum = withContext(Dispatchers.Default) {
                        "sum 1..$n = ${Lean.sumTo(n)}"
                    }
                }
            }) { Text("sum a Lean list") }
        }

        if (listSum.isNotEmpty()) {
            Text(listSum, style = MaterialTheme.typography.bodyLarge)
        }

        if (factorial.isNotEmpty()) {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("$n! = ${factorial.length} digits",
                         style = MaterialTheme.typography.labelLarge)
                    Text(factorial,
                         fontFamily = FontFamily.Monospace,
                         style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}
