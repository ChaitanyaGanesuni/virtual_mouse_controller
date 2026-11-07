package com.retroplay.app.core.designsystem.theme

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

val RetroBlack = Color(0xFF000000)
val RetroCharcoal = Color(0xFF111116)
val RetroCharcoalElevated = Color(0xFF1A1A22)
val RetroCharcoalHigh = Color(0xFF24242E)
val RetroOutline = Color(0xFF34343F)
val RetroOutlineVariant = Color(0xFF23232C)

val RetroPurple = Color(0xFF8B5CF6)
val RetroPurpleDeep = Color(0xFF5B21B6)
val RetroPurpleContainer = Color(0xFF2A1858)
val ElectricBlue = Color(0xFF22B8FF)
val ElectricBlueDeep = Color(0xFF0A6FD6)
val ElectricBlueContainer = Color(0xFF0A324D)

val RetroTextPrimary = Color(0xFFF4F4F8)
val RetroTextSecondary = Color(0xFFA7A7BA)

val RetroSuccess = Color(0xFF34D399)
val RetroWarning = Color(0xFFFBBF24)
val RetroError = Color(0xFFF87171)

object RetroGradients {
    val Accent: Brush = Brush.linearGradient(listOf(RetroPurple, ElectricBlue))
    val Hero: Brush = Brush.linearGradient(listOf(RetroPurpleDeep, RetroCharcoalElevated, ElectricBlueDeep))
}
