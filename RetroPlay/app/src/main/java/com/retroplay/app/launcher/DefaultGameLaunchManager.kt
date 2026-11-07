package com.retroplay.app.launcher

import com.retroplay.app.core.coroutines.IoDispatcher
import com.retroplay.app.domain.launch.GameLaunchManager
import com.retroplay.app.domain.launch.InstalledApp
import com.retroplay.app.domain.launch.LaunchPlan
import com.retroplay.app.domain.launch.LaunchResult
import com.retroplay.app.domain.model.ExecutionType
import com.retroplay.app.domain.model.Game
import com.retroplay.app.domain.model.InstallationStatus
import com.retroplay.app.domain.repository.GameRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class DefaultGameLaunchManager @Inject constructor(
    private val androidLauncher: AndroidGameLauncher,
    private val externalLauncher: ExternalEmulatorLauncher,
    private val unsupportedHandler: UnsupportedGameHandler,
    private val packageInspector: PackageInspector,
    private val appStarter: AppStarter,
    private val gameRepository: GameRepository,
    @IoDispatcher private val ioDispatcher: CoroutineDispatcher,
) : GameLaunchManager {

    override suspend fun plan(game: Game): LaunchPlan = withContext(ioDispatcher) {
        val plan = when {
            unsupportedHandler.isUnsupported(game) -> LaunchPlan.Unsupported(unsupportedHandler.explain(game))
            game.executionType == ExecutionType.ANDROID_NATIVE -> androidLauncher.plan(game)
            else -> externalLauncher.plan(game)
        }
        syncAndroidInstallation(game, plan)
        plan
    }

    override suspend fun launch(game: Game): LaunchResult = withContext(ioDispatcher) {
        val result = when {
            unsupportedHandler.isUnsupported(game) ->
                LaunchResult.NotStarted(LaunchPlan.Unsupported(unsupportedHandler.explain(game)))
            game.executionType == ExecutionType.ANDROID_NATIVE -> androidLauncher.launch(game)
            else -> externalLauncher.launch(game)
        }
        if (result is LaunchResult.Started) {
            gameRepository.recordLaunch(game.id, result.method, System.currentTimeMillis())
        }
        result
    }

    override suspend fun launchableApps(): List<InstalledApp> = withContext(ioDispatcher) {
        packageInspector.launchableApps()
    }

    override fun openStoreListing(packageName: String): Boolean = appStarter.openStoreListing(packageName)

    /** Keeps the stored installation status of Android games in step with what is actually installed. */
    private suspend fun syncAndroidInstallation(game: Game, plan: LaunchPlan) {
        val status = when (plan) {
            is LaunchPlan.AndroidReady -> InstallationStatus.INSTALLED
            is LaunchPlan.AndroidNotInstalled ->
                if (game.installationStatus in setOf(InstallationStatus.INSTALLED, InstallationStatus.MISSING)) InstallationStatus.MISSING
                else InstallationStatus.NOT_INSTALLED
            else -> return
        }
        if (status != game.installationStatus) gameRepository.updateInstallationStatus(game.id, status)
    }
}
