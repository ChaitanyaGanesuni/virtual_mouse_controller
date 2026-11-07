package com.retroplay.app.launcher

import com.retroplay.app.domain.launch.UnsupportedInfo
import com.retroplay.app.domain.model.CompatibilityStatus
import com.retroplay.app.domain.model.ExecutionType
import com.retroplay.app.domain.model.Game
import com.retroplay.app.domain.model.GamePlatform
import javax.inject.Inject

/** Explains why a game cannot be launched, what it needs, and whether that conclusion comes from a test. */
class UnsupportedGameHandler @Inject constructor() {

    fun isUnsupported(game: Game): Boolean =
        game.executionType == ExecutionType.UNSUPPORTED || game.compatibilityStatus == CompatibilityStatus.UNSUPPORTED

    fun explain(game: Game): UnsupportedInfo {
        val reasons = buildList {
            if (game.executionType == ExecutionType.UNSUPPORTED) {
                add("No supported way to run ${game.title} on Android is configured.")
            }
            if (game.compatibilityStatus == CompatibilityStatus.UNSUPPORTED) {
                add("A compatibility test on this device recorded it as unsupported.")
            }
        }
        val environment = when (game.originalPlatform) {
            GamePlatform.WINDOWS_PC -> "Windows PC: needs an external Windows compatibility app with a working graphics backend."
            GamePlatform.ANDROID -> "Android: needs the official app installed from its store."
        }
        val tested = when (game.compatibilityStatus) {
            CompatibilityStatus.NOT_TESTED -> "Not tested on this device. This is not a test result."
            else -> "Tested on this device: ${game.compatibilityStatus.label}."
        }
        return UnsupportedInfo(reasons, environment, tested)
    }
}
