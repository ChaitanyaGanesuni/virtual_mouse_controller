package com.retroplay.app.testutil

import com.retroplay.app.compatibility.device.DeviceProfileManager
import com.retroplay.app.domain.device.DeviceProfileComparator
import com.retroplay.app.domain.model.ComparisonRow
import com.retroplay.app.domain.model.DeviceProfile
import com.retroplay.app.domain.model.ReferenceDeviceProfile
import com.retroplay.app.domain.model.ReferenceProfiles
import com.retroplay.app.domain.repository.UserPreferences
import com.retroplay.app.domain.repository.UserPreferencesRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update

class FakeDeviceProfileManager(
    var nextProfile: DeviceProfile = TestProfiles.pixel9Like(),
    var failure: Exception? = null,
) : DeviceProfileManager {
    var captureCount = 0
        private set

    override val referenceProfile: ReferenceDeviceProfile = ReferenceProfiles.Pixel9

    override suspend fun captureProfile(): DeviceProfile {
        captureCount++
        failure?.let { throw it }
        return nextProfile
    }

    override fun compareWithReference(profile: DeviceProfile): List<ComparisonRow> =
        DeviceProfileComparator.compare(profile, referenceProfile)
}

class FakeUserPreferencesRepository(initial: UserPreferences = UserPreferences()) : UserPreferencesRepository {
    private val state = MutableStateFlow(initial)
    override val preferences: Flow<UserPreferences> = state

    override suspend fun setShowReferenceComparison(enabled: Boolean) {
        state.update { it.copy(showReferenceComparison = enabled) }
    }

    override suspend fun setExternalApp(packageName: String?, label: String?) {
        state.update { it.copy(externalAppPackage = packageName, externalAppLabel = if (packageName == null) null else label) }
    }
}

class FakeGameRepository(
    initial: List<com.retroplay.app.domain.model.Game> = com.retroplay.app.domain.game.GameCatalogue.initialGames,
) : com.retroplay.app.domain.repository.GameRepository {
    val games = MutableStateFlow(initial)

    override fun observeGames(): Flow<List<com.retroplay.app.domain.model.Game>> = games

    override fun observeGame(id: String): Flow<com.retroplay.app.domain.model.Game?> =
        kotlinx.coroutines.flow.flow { games.collect { list -> emit(list.firstOrNull { it.id == id }) } }

    override suspend fun setFavorite(id: String, favorite: Boolean) {
        games.update { list -> list.map { if (it.id == id) it.copy(isFavorite = favorite) else it } }
    }

    override suspend fun updateNotes(id: String, notes: String) {
        games.update { list -> list.map { if (it.id == id) it.copy(userNotes = notes.trim()) else it } }
    }

    val launches = mutableListOf<Triple<String, com.retroplay.app.domain.launch.LaunchMethod, Long>>()

    override suspend fun setAndroidPackage(id: String, packageName: String?) {
        games.update { list -> list.map { if (it.id == id) it.copy(androidPackageName = packageName) else it } }
    }

    override suspend fun updateInstallationStatus(id: String, status: com.retroplay.app.domain.model.InstallationStatus) {
        games.update { list -> list.map { if (it.id == id) it.copy(installationStatus = status) else it } }
    }

    override suspend fun recordLaunch(id: String, method: com.retroplay.app.domain.launch.LaunchMethod, atEpochMillis: Long) {
        launches += Triple(id, method, atEpochMillis)
        if (method == com.retroplay.app.domain.launch.LaunchMethod.ANDROID_APP) {
            games.update { list -> list.map { if (it.id == id) it.copy(lastPlayedAtEpochMillis = atEpochMillis) else it } }
        }
    }
}

/** Simulates the set of apps visible to RetroPlay. */
class FakePackageInspector(vararg apps: com.retroplay.app.domain.launch.InstalledApp) : com.retroplay.app.launcher.PackageInspector {
    val installed = apps.toMutableList()
    override fun launchableApp(packageName: String) = installed.firstOrNull { it.packageName == packageName }
    override fun launchableApps() = installed.sortedBy { it.label }
}

class FakeAppStarter(var failWith: Exception? = null, var storeAvailable: Boolean = true) : com.retroplay.app.launcher.AppStarter {
    val started = mutableListOf<String>()
    val storeOpened = mutableListOf<String>()
    override fun startApp(packageName: String): Result<Unit> {
        failWith?.let { return Result.failure(it) }
        started += packageName
        return Result.success(Unit)
    }
    override fun openStoreListing(packageName: String): Boolean {
        if (storeAvailable) storeOpened += packageName
        return storeAvailable
    }
}

class FakeGameLaunchManager(
    var apps: List<com.retroplay.app.domain.launch.InstalledApp> = listOf(
        com.retroplay.app.domain.launch.InstalledApp("com.example.windowsrunner", "Windows Runner"),
    ),
    var nextPlan: com.retroplay.app.domain.launch.LaunchPlan =
        com.retroplay.app.domain.launch.LaunchPlan.ExternalNotConfigured(emptyList(), ""),
    var nextResult: com.retroplay.app.domain.launch.LaunchResult =
        com.retroplay.app.domain.launch.LaunchResult.NotStarted(nextPlan),
    var storeAvailable: Boolean = true,
) : com.retroplay.app.domain.launch.GameLaunchManager {
    var planCalls = 0
    val launched = mutableListOf<String>()
    override suspend fun plan(game: com.retroplay.app.domain.model.Game) = nextPlan.also { planCalls++ }
    override suspend fun launch(game: com.retroplay.app.domain.model.Game) = nextResult.also { launched += game.id }
    override suspend fun launchableApps() = apps
    override fun openStoreListing(packageName: String) = storeAvailable
}
