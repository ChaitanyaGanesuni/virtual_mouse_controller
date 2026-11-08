package com.retroplay.app.presentation.common

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.SportsCricket
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import com.retroplay.app.core.designsystem.theme.ElectricBlue
import com.retroplay.app.core.designsystem.theme.RetroError
import com.retroplay.app.core.designsystem.theme.RetroSuccess
import com.retroplay.app.core.designsystem.theme.RetroTextSecondary
import com.retroplay.app.core.designsystem.theme.RetroWarning
import com.retroplay.app.domain.model.CompatibilityStatus
import com.retroplay.app.domain.model.ExecutionType
import com.retroplay.app.domain.model.GameCategory

val GameCategory.icon: ImageVector
    get() = when (this) {
        GameCategory.CRICKET -> Icons.Filled.SportsCricket
        GameCategory.GTA -> Icons.Filled.DirectionsCar
        GameCategory.OTHER -> Icons.Filled.SportsEsports
    }

val CompatibilityStatus.color: Color
    get() = when (this) {
        CompatibilityStatus.NOT_TESTED -> RetroTextSecondary
        CompatibilityStatus.EXPERIMENTAL -> RetroWarning
        CompatibilityStatus.WORKING -> ElectricBlue
        CompatibilityStatus.PLAYABLE -> RetroSuccess
        CompatibilityStatus.UNSTABLE -> Color(0xFFFB923C)
        CompatibilityStatus.UNSUPPORTED -> RetroError
    }

val CompatibilityStatus.explanation: String
    get() = when (this) {
        CompatibilityStatus.NOT_TESTED -> "No test has been recorded on this device yet."
        CompatibilityStatus.EXPERIMENTAL -> "Starts in testing, but the setup is still being explored."
        CompatibilityStatus.WORKING -> "Runs in testing, with noticeable issues."
        CompatibilityStatus.PLAYABLE -> "Tested and playable start to finish with acceptable performance."
        CompatibilityStatus.UNSTABLE -> "Runs in testing but crashes or freezes too often."
        CompatibilityStatus.UNSUPPORTED -> "Testing showed it cannot run in the available environment."
    }

val ExecutionType.explanation: String
    get() = when (this) {
        ExecutionType.ANDROID_NATIVE ->
            "An official Android app. It must be installed from its store; RetroPlay never installs apps."
        ExecutionType.EXTERNAL_EMULATOR ->
            "A Windows PC game. It needs your own legally obtained copy and an external Windows " +
                "compatibility app (such as Winlator) that you install and configure yourself. " +
                "RetroPlay does not include either."
        ExecutionType.UNSUPPORTED -> "No supported way to run this game on Android is known."
    }
