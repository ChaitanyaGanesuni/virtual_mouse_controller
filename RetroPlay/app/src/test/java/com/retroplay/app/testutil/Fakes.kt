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
