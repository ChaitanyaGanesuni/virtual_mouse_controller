package com.retroplay.app.domain.device

import com.retroplay.app.core.util.Formatters
import com.retroplay.app.domain.model.ComparisonField
import com.retroplay.app.domain.model.ComparisonRow
import com.retroplay.app.domain.model.ComparisonVerdict
import com.retroplay.app.domain.model.DeviceProfile
import com.retroplay.app.domain.model.ReferenceDeviceProfile
import kotlin.math.abs

/** Compares a measured [DeviceProfile] against a [ReferenceDeviceProfile]. Pure and side-effect free. */
object DeviceProfileComparator {

    /** OS-visible RAM is always below installed RAM; accept 80%–105% of the reference as a match. */
    const val RAM_LOWER_RATIO = 0.80
    const val RAM_UPPER_RATIO = 1.05
    private const val REFRESH_TOLERANCE_HZ = 1.0f

    fun compare(profile: DeviceProfile, reference: ReferenceDeviceProfile): List<ComparisonRow> = listOf(
        model(profile, reference),
        android(profile, reference),
        soc(profile, reference),
        gpu(profile, reference),
        abi(profile, reference),
        memory(profile, reference),
        resolution(profile, reference),
        refreshRate(profile, reference),
    )

    private fun model(p: DeviceProfile, r: ReferenceDeviceProfile) = ComparisonRow(
        field = ComparisonField.MODEL,
        reference = r.modelName,
        measured = p.identity.model,
        verdict = verdict(p.identity.model.equals(r.modelName, ignoreCase = true)),
    )

    private fun android(p: DeviceProfile, r: ReferenceDeviceProfile) = ComparisonRow(
        field = ComparisonField.ANDROID_VERSION,
        reference = "${r.minimumAndroidVersion} (API ${r.minimumApiLevel}) or later",
        measured = "Android ${p.os.release} (API ${p.os.apiLevel})",
        verdict = verdict(p.os.apiLevel >= r.minimumApiLevel),
    )

    private fun soc(p: DeviceProfile, r: ReferenceDeviceProfile): ComparisonRow {
        val reported = p.identity.socModel
        val measured = listOfNotNull(p.identity.socManufacturer, reported).joinToString(" ")
        return ComparisonRow(
            field = ComparisonField.SOC,
            reference = r.socName,
            measured = measured.ifEmpty { "Not reported" },
            verdict = when {
                reported == null -> ComparisonVerdict.UNAVAILABLE
                else -> verdict(r.socAliases.any { reported.contains(it, ignoreCase = true) })
            },
        )
    }

    private fun gpu(p: DeviceProfile, r: ReferenceDeviceProfile): ComparisonRow {
        val renderer = p.gpu.renderer
        return ComparisonRow(
            field = ComparisonField.GPU,
            reference = r.gpuName,
            measured = renderer ?: "Not obtainable",
            verdict = when {
                renderer == null -> ComparisonVerdict.UNAVAILABLE
                else -> verdict(renderer.contains(r.gpuRendererMatch, ignoreCase = true))
            },
            note = "GL_RENDERER does not report the shader-core count.",
        )
    }

    private fun abi(p: DeviceProfile, r: ReferenceDeviceProfile): ComparisonRow {
        val primary = p.cpu.primaryAbi
        return ComparisonRow(
            field = ComparisonField.CPU_ARCHITECTURE,
            reference = r.primaryAbi,
            measured = primary ?: "Not reported",
            verdict = if (primary == null) ComparisonVerdict.UNAVAILABLE else verdict(primary == r.primaryAbi),
        )
    }

    private fun memory(p: DeviceProfile, r: ReferenceDeviceProfile): ComparisonRow {
        val total = p.memory.totalBytes
        val ratio = total.toDouble() / r.ramBytes.toDouble()
        return ComparisonRow(
            field = ComparisonField.MEMORY,
            reference = Formatters.bytes(r.ramBytes, binary = true),
            measured = if (total > 0) Formatters.bytes(total, binary = true) else "Not reported",
            verdict = when {
                total <= 0 -> ComparisonVerdict.UNAVAILABLE
                else -> verdict(ratio in RAM_LOWER_RATIO..RAM_UPPER_RATIO)
            },
            note = "Android reports OS-visible memory, which is lower than installed RAM.",
        )
    }

    private fun resolution(p: DeviceProfile, r: ReferenceDeviceProfile): ComparisonRow {
        val w = p.display.widthPx
        val h = p.display.heightPx
        val matches = (w == r.displayWidthPx && h == r.displayHeightPx) ||
            (w == r.displayHeightPx && h == r.displayWidthPx)
        return ComparisonRow(
            field = ComparisonField.RESOLUTION,
            reference = "${r.displayWidthPx} × ${r.displayHeightPx}",
            measured = "${minOf(w, h)} × ${maxOf(w, h)}",
            verdict = if (w <= 0 || h <= 0) ComparisonVerdict.UNAVAILABLE else verdict(matches),
        )
    }

    private fun refreshRate(p: DeviceProfile, r: ReferenceDeviceProfile): ComparisonRow {
        val max = p.display.maxRefreshRateHz
        return ComparisonRow(
            field = ComparisonField.REFRESH_RATE,
            reference = Formatters.refreshRate(r.maxRefreshRateHz),
            measured = Formatters.refreshRate(max),
            verdict = if (max <= 0f) ComparisonVerdict.UNAVAILABLE else verdict(abs(max - r.maxRefreshRateHz) <= REFRESH_TOLERANCE_HZ),
        )
    }

    private fun verdict(matches: Boolean) = if (matches) ComparisonVerdict.MATCH else ComparisonVerdict.DIFFERENT
}
