package com.retroplay.app.domain.model

enum class ComparisonField(val label: String) {
    MODEL("Model"),
    ANDROID_VERSION("Android version"),
    SOC("System on chip"),
    GPU("GPU"),
    CPU_ARCHITECTURE("CPU architecture"),
    MEMORY("Memory"),
    RESOLUTION("Display resolution"),
    REFRESH_RATE("Max refresh rate"),
}

enum class ComparisonVerdict { MATCH, DIFFERENT, UNAVAILABLE }

data class ComparisonRow(
    val field: ComparisonField,
    val reference: String,
    val measured: String,
    val verdict: ComparisonVerdict,
    val note: String? = null,
)
