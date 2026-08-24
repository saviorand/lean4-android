package com.leanandroid.compose

/**
 * The Lean runtime. Loading libleanshared.so takes a couple of minutes on first
 * launch because it is ~160 MB, so callers should treat [init] as slow.
 */
object Lean {
    init {
        System.loadLibrary("leanshared")
        System.loadLibrary("leanbridge")
    }

    external fun init(): Boolean
    external fun version(): String
    external fun factorial(n: Int): String
    external fun sumTo(n: Int): Long
}
