package com.retroplay.app.core.util

import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

object Formatters {
    private const val KIB = 1024.0
    private const val KB = 1000.0

    /**
     * Formats a byte count. RAM uses binary units ([binary] = true, matching how phone RAM is marketed);
     * storage uses decimal units, matching Android's own Settings > Storage screen.
     */
    fun bytes(bytes: Long, binary: Boolean): String {
        if (bytes < 0) return "Unknown"
        val unit = if (binary) KIB else KB
        if (bytes < unit) return "$bytes B"
        val units = listOf("KB", "MB", "GB", "TB")
        var value = bytes.toDouble()
        var index = -1
        while (value >= unit && index < units.lastIndex) {
            value /= unit
            index++
        }
        return String.format(Locale.US, "%.1f %s", value, units[index])
    }

    fun refreshRate(hz: Float): String {
        val rounded = hz.roundToInt()
        return if (abs(hz - rounded) < 0.05f) "$rounded Hz" else String.format(Locale.US, "%.1f Hz", hz)
    }

    fun khzToGhz(khz: Long): String = String.format(Locale.US, "%.2f GHz", khz / 1_000_000.0)

    fun yesNo(value: Boolean): String = if (value) "Yes" else "No"
}
