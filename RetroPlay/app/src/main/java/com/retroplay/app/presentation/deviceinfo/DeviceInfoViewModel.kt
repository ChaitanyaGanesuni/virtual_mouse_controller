package com.retroplay.app.presentation.deviceinfo

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.retroplay.app.compatibility.device.DeviceProfileManager
import com.retroplay.app.domain.model.ComparisonRow
import com.retroplay.app.domain.model.DeviceProfile
import com.retroplay.app.domain.model.ReferenceDeviceProfile
import com.retroplay.app.domain.repository.UserPreferencesRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface DeviceInfoUiState {
    data object Loading : DeviceInfoUiState
    data class Error(val message: String) : DeviceInfoUiState
    data class Ready(
        val profile: DeviceProfile,
        val sections: List<InfoSection>,
        val reference: ReferenceDeviceProfile,
        val comparison: List<ComparisonRow>,
        val showComparison: Boolean,
    ) : DeviceInfoUiState
}

@HiltViewModel
class DeviceInfoViewModel @Inject constructor(
    private val deviceProfileManager: DeviceProfileManager,
    userPreferencesRepository: UserPreferencesRepository,
) : ViewModel() {

    private sealed interface Capture {
        data object InProgress : Capture
        data class Done(val profile: DeviceProfile) : Capture
        data class Failed(val message: String) : Capture
    }

    private val capture = MutableStateFlow<Capture>(Capture.InProgress)

    val uiState: StateFlow<DeviceInfoUiState> = combine(capture, userPreferencesRepository.preferences) { c, prefs ->
        when (c) {
            Capture.InProgress -> DeviceInfoUiState.Loading
            is Capture.Failed -> DeviceInfoUiState.Error(c.message)
            is Capture.Done -> DeviceInfoUiState.Ready(
                profile = c.profile,
                sections = DeviceInfoSections.from(c.profile),
                reference = deviceProfileManager.referenceProfile,
                comparison = deviceProfileManager.compareWithReference(c.profile),
                showComparison = prefs.showReferenceComparison,
            )
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DeviceInfoUiState.Loading)

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            capture.value = Capture.InProgress
            capture.value = try {
                Capture.Done(deviceProfileManager.captureProfile())
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Capture.Failed(e.message ?: "Could not read device information")
            }
        }
    }
}
