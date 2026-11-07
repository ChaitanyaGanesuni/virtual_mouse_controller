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
}
