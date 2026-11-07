package com.retroplay.app.core.designsystem.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

private val RetroColorScheme = darkColorScheme(
    primary = RetroPurple,
    onPrimary = Color.White,
    primaryContainer = RetroPurpleContainer,
    onPrimaryContainer = Color(0xFFE9DDFF),
    secondary = ElectricBlue,
    onSecondary = RetroBlack,
    secondaryContainer = ElectricBlueContainer,
    onSecondaryContainer = Color(0xFFCDEBFF),
    tertiary = ElectricBlue,
    onTertiary = RetroBlack,
    background = RetroBlack,
    onBackground = RetroTextPrimary,
    surface = RetroBlack,
    onSurface = RetroTextPrimary,
    surfaceVariant = RetroCharcoalElevated,
    onSurfaceVariant = RetroTextSecondary,
    surfaceContainerLowest = RetroBlack,
    surfaceContainerLow = RetroCharcoal,
    surfaceContainer = RetroCharcoal,
    surfaceContainerHigh = RetroCharcoalElevated,
    surfaceContainerHighest = RetroCharcoalHigh,
    outline = RetroOutline,
    outlineVariant = RetroOutlineVariant,
    error = RetroError,
    onError = RetroBlack,
)

private val RetroShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(20.dp),
    extraLarge = RoundedCornerShape(28.dp),
)

/** RetroPlay is dark-only by design: black and charcoal surfaces with purple / electric-blue accents. */
@Composable
fun RetroPlayTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = RetroColorScheme,
        typography = RetroTypography,
        shapes = RetroShapes,
        content = content,
    )
}
