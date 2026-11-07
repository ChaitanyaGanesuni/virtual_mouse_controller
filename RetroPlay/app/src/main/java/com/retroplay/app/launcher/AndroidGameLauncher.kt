package com.retroplay.app.launcher

import com.retroplay.app.domain.launch.LaunchMethod
import com.retroplay.app.domain.launch.LaunchPlan
import com.retroplay.app.domain.launch.LaunchResult
import com.retroplay.app.domain.model.Game
import javax.inject.Inject

/** Launches officially installed Android games through their normal launcher activity. */
class AndroidGameLauncher @Inject constructor(
    private val packageInspector: PackageInspector,
    private val appStarter: AppStarter,
) {
    fun plan(game: Game): LaunchPlan {
        val pkg = game.androidPackageName
        val app = pkg?.let(packageInspector::launchableApp)
        return if (app != null) {
            LaunchPlan.AndroidReady(app)
        } else {
            LaunchPlan.AndroidNotInstalled(pkg, installationGuidance(pkg))
        }
    }

    fun launch(game: Game): LaunchResult = when (val plan = plan(game)) {
        is LaunchPlan.AndroidReady -> appStarter.startApp(plan.app.packageName).fold(
            onSuccess = { LaunchResult.Started(plan.app, LaunchMethod.ANDROID_APP) },
            onFailure = { LaunchResult.Failed("Could not open ${plan.app.label}: ${it.message ?: "unknown error"}") },
        )
        else -> LaunchResult.NotStarted(plan)
    }

    private fun installationGuidance(pkg: String?): List<String> = buildList {
        if (pkg != null) {
            add("This game's app ($pkg) is not installed on this phone.")
            add("Install it yourself from its store listing using the account that owns it. RetroPlay never installs apps.")
        } else {
            add("No Android app is linked to this game yet.")
        }
        add("If you own a different edition, install it, then use “Link installed app” to choose it.")
    }
}
