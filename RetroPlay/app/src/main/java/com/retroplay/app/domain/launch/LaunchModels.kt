package com.retroplay.app.domain.launch

import com.retroplay.app.domain.model.Game

/** An installed app with a launcher entry, as visible to RetroPlay under package-visibility rules. */
data class InstalledApp(val packageName: String, val label: String)

enum class LaunchMethod { ANDROID_APP, EXTERNAL_APP_OPENED }

data class UnsupportedInfo(
    val reasons: List<String>,
    val requiredEnvironment: String,
    val testStatus: String,
)

/** What RetroPlay can honestly do for a game right now. Computed before any launch attempt. */
sealed interface LaunchPlan {
    /** The official Android app is installed and has a launcher activity. */
    data class AndroidReady(val app: InstalledApp) : LaunchPlan

    /** The Android app is not installed (or not linked). Nothing is installed automatically. */
    data class AndroidNotInstalled(val expectedPackage: String?, val guidance: List<String>) : LaunchPlan

    /** A Windows game: RetroPlay can open the user's chosen compatibility app; the rest is manual. */
    data class ExternalReady(val app: InstalledApp, val steps: List<String>, val note: String) : LaunchPlan

    /** No compatibility app chosen yet. */
    data class ExternalNotConfigured(val steps: List<String>, val note: String) : LaunchPlan

    /** The chosen compatibility app is no longer installed. */
    data class ExternalAppMissing(val configuredLabel: String, val steps: List<String>) : LaunchPlan

    data class Unsupported(val info: UnsupportedInfo) : LaunchPlan
}

sealed interface LaunchResult {
    data class Started(val app: InstalledApp, val method: LaunchMethod) : LaunchResult
    /** The game cannot be started; the plan explains why and what to do. */
    data class NotStarted(val plan: LaunchPlan) : LaunchResult
    data class Failed(val message: String) : LaunchResult
}

interface GameLaunchManager {
    suspend fun plan(game: Game): LaunchPlan
    suspend fun launch(game: Game): LaunchResult
    /** Apps with a launcher activity, for linking an Android game or choosing a compatibility app. */
    suspend fun launchableApps(): List<InstalledApp>
    /** Opens the store listing so the user can install the app themselves. Returns false if no store is available. */
    fun openStoreListing(packageName: String): Boolean
}
