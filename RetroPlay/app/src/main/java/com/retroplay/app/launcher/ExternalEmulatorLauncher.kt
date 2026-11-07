package com.retroplay.app.launcher

import com.retroplay.app.domain.launch.InstalledApp
import com.retroplay.app.domain.launch.LaunchMethod
import com.retroplay.app.domain.launch.LaunchPlan
import com.retroplay.app.domain.launch.LaunchResult
import com.retroplay.app.domain.model.Game
import com.retroplay.app.domain.repository.UserPreferencesRepository
import kotlinx.coroutines.flow.first
import javax.inject.Inject

/**
 * Integration with a user-chosen external Windows compatibility app (for example Winlator).
 *
 * No package name, intent action or deep link is assumed: the user picks the app, and RetroPlay only
 * opens it through its standard launcher intent. Starting the game inside it is a manual step,
 * and RetroPlay never changes the app's configuration.
 */
class ExternalEmulatorLauncher @Inject constructor(
    private val packageInspector: PackageInspector,
    private val appStarter: AppStarter,
    private val preferences: UserPreferencesRepository,
) {
    suspend fun plan(game: Game): LaunchPlan {
        val prefs = preferences.preferences.first()
        val configured = prefs.externalAppPackage
        return when {
            configured == null -> LaunchPlan.ExternalNotConfigured(manualSteps(game, null), NO_DIRECT_LAUNCH_NOTE)
            else -> when (val app = packageInspector.launchableApp(configured)) {
                null -> LaunchPlan.ExternalAppMissing(prefs.externalAppLabel ?: configured, manualSteps(game, null))
                else -> LaunchPlan.ExternalReady(app, manualSteps(game, app), NO_DIRECT_LAUNCH_NOTE)
            }
        }
    }

    suspend fun launch(game: Game): LaunchResult = when (val plan = plan(game)) {
        is LaunchPlan.ExternalReady -> appStarter.startApp(plan.app.packageName).fold(
            onSuccess = { LaunchResult.Started(plan.app, LaunchMethod.EXTERNAL_APP_OPENED) },
            onFailure = { LaunchResult.Failed("Could not open ${plan.app.label}: ${it.message ?: "unknown error"}") },
        )
        else -> LaunchResult.NotStarted(plan)
    }

    companion object {
        const val NO_DIRECT_LAUNCH_NOTE =
            "RetroPlay opens the compatibility app but cannot start the game inside it: no public launch " +
                "interface is assumed. Files you imported into RetroPlay may not be visible to the other app; " +
                "copy your game folder to a location that app can read (for example its own drive or a shared folder)."

        fun manualSteps(game: Game, app: InstalledApp?): List<String> {
            val name = app?.label ?: "your Windows compatibility app"
            return listOf(
                "Open $name.",
                "Start the Windows environment (container) you set up for games.",
                "Make sure your legally owned copy of ${game.title} is in a folder that $name can access.",
                "Use $name's file manager to run the game's executable (.exe).",
                "Afterwards, record how it ran so the compatibility status reflects a real test.",
            )
        }
    }
}
