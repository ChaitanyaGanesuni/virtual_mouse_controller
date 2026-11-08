package com.retroplay.app.core.time

/** Injectable time source so time-dependent logic is testable. */
fun interface Clock {
    fun nowMillis(): Long
}
