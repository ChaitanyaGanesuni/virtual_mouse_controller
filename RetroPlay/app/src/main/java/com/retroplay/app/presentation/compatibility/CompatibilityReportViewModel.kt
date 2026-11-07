package com.retroplay.app.presentation.compatibility

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.retroplay.app.compatibility.device.DeviceProfileManager
import com.retroplay.app.domain.model.CompatibilityStatus
import com.retroplay.app.domain.model.Game
import com.retroplay.app.domain.repository.GameRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

data class DeviceSummary(val model: String, val android: String, val gpu: String)

data class CompatibilityReportUiState(
    val isLoading: Boolean = true,
    val device: DeviceSummary? = null,
    val statusCounts: Map<CompatibilityStatus, Int> = emptyMap(),
    val games: List<Game> = emptyList(),
) {
    val testedCount: Int get() = games.count { it.compatibilityStatus != CompatibilityStatus.NOT_TESTED }
}

@HiltViewModel
class CompatibilityReportViewModel @Inject constructor(
    gameRepository: GameRepository,
    private val deviceProfileManager: DeviceProfileManager,
) : ViewModel() {

    private val device = MutableStateFlow<DeviceSummary?>(null)

    val uiState: StateFlow<CompatibilityReportUiState> =
        combine(gameRepository.observeGames(), device) { games, d ->
            CompatibilityReportUiState(
                isLoading = false,
                device = d,
                statusCounts = CompatibilityStatus.entries.associateWith { s -> games.count { it.compatibilityStatus == s } },
                games = games,
            )
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), CompatibilityReportUiState())

    init {
        viewModelScope.launch {
            device.value = try {
                val p = deviceProfileManager.captureProfile()
                DeviceSummary(
                    model = "${p.identity.manufacturer} ${p.identity.model}",
                    android = "Android ${p.os.release} (API ${p.os.apiLevel})",
                    gpu = p.gpu.renderer ?: "Not obtainable",
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                null
            }
        }
    }
}
