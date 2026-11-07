package com.retroplay.app.domain.model

/**
 * Published specifications of a target device. These are reference values for comparison only
 * and are never presented as runtime measurements.
 */
data class ReferenceDeviceProfile(
    val displayName: String,
    val modelName: String,
    val socName: String,
    /** Names the platform may report for this SoC via Build.SOC_MODEL (case-insensitive match). */
    val socAliases: List<String>,
    val gpuName: String,
    /** Substring expected in GL_RENDERER (drivers do not report the shader-core count, e.g. "MC7"). */
    val gpuRendererMatch: String,
    val ramBytes: Long,
    val primaryAbi: String,
    val displayWidthPx: Int,
    val displayHeightPx: Int,
    val displayDiagonalInches: Double,
    val maxRefreshRateHz: Float,
    val minimumApiLevel: Int,
    val minimumAndroidVersion: String,
)

object ReferenceProfiles {
    private const val GIB = 1024L * 1024L * 1024L

    /** Google Pixel 9 specification sheet (the RetroPlay target device). */
    val Pixel9 = ReferenceDeviceProfile(
        displayName = "Google Pixel 9",
        modelName = "Pixel 9",
        socName = "Google Tensor G4",
        socAliases = listOf("Tensor G4"),
        gpuName = "ARM Mali-G715 MC7",
        gpuRendererMatch = "Mali-G715",
        ramBytes = 12 * GIB,
        primaryAbi = "arm64-v8a",
        displayWidthPx = 1080,
        displayHeightPx = 2424,
        displayDiagonalInches = 6.3,
        maxRefreshRateHz = 120f,
        minimumApiLevel = 35,
        minimumAndroidVersion = "Android 15",
    )
}
