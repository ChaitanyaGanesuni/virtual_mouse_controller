package com.retroplay.app.presentation.gamedetail

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.retroplay.app.domain.launch.GameLaunchManager
import com.retroplay.app.domain.launch.InstalledApp
import com.retroplay.app.domain.launch.LaunchMethod
import com.retroplay.app.domain.launch.LaunchPlan
import com.retroplay.app.domain.launch.LaunchResult
import com.retroplay.app.domain.model.Game
import com.retroplay.app.domain.repository.GameRepository
import com.retroplay.app.domain.repository.UserPreferencesRepository
import com.retroplay.app.presentation.common.AppPickerState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface GameDetailUiState {
    data object Loading : GameDetailUiState
    data object NotFound : GameDetailUiState
    data class Ready(val game: Game, val launchPlan: LaunchPlan?) : GameDetailUiState
}

enum class PickerPurpose { LINK_ANDROID_APP, CHOOSE_EXTERNAL_APP }

@OptIn(ExperimentalCoroutinesApi::class)
@HiltViewModel
class GameDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val gameRepository: GameRepository,
    private val launchManager: GameLaunchManager,
    private val preferences: UserPreferencesRepository,
) : ViewModel() {

    /** Matches the `gameId` property of the type-safe GameDetailRoute. */
    private val gameId: String = checkNotNull(savedStateHandle[GAME_ID_ARG]) { "gameId argument missing" }
    private val refreshTrigger = MutableStateFlow(0)

    val uiState: StateFlow<GameDetailUiState> =
        combine(gameRepository.observeGame(gameId), preferences.preferences, refreshTrigger) { game, _, _ -> game }
            .mapLatest { game ->
                if (game == null) GameDetailUiState.NotFound
                else GameDetailUiState.Ready(game, launchManager.plan(game))
            }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), GameDetailUiState.Loading)

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    private val _picker = MutableStateFlow<Pair<PickerPurpose, AppPickerState>?>(null)
    val picker: StateFlow<Pair<PickerPurpose, AppPickerState>?> = _picker.asStateFlow()

    /** Re-checks installed apps, e.g. when returning from the Play Store. */
    fun refresh() = refreshTrigger.update { it + 1 }

    fun setFavorite(favorite: Boolean) {
        viewModelScope.launch { gameRepository.setFavorite(gameId, favorite) }
    }

    fun saveNotes(notes: String) {
        viewModelScope.launch { gameRepository.updateNotes(gameId, notes) }
    }

    fun launch() {
        val game = (uiState.value as? GameDetailUiState.Ready)?.game ?: return
        viewModelScope.launch {
            _message.value = when (val result = launchManager.launch(game)) {
                is LaunchResult.Started -> when (result.method) {
                    LaunchMethod.ANDROID_APP -> null
                    LaunchMethod.EXTERNAL_APP_OPENED -> "Opened ${result.app.label}. Start the game from there."
                }
                is LaunchResult.Failed -> result.message
                is LaunchResult.NotStarted -> "This game can't be started right now. See the details below."
            }
            refresh()
        }
    }

    fun openStoreListing(packageName: String) {
        if (!launchManager.openStoreListing(packageName)) {
            _message.value = "No app store is available to open the listing."
        }
    }

    fun showPicker(purpose: PickerPurpose) {
        val base = when (purpose) {
            PickerPurpose.LINK_ANDROID_APP -> AppPickerState(
                title = "Link installed app",
                description = "Choose the installed app for this game. Only apps with a launcher icon are listed.",
            )
            PickerPurpose.CHOOSE_EXTERNAL_APP -> AppPickerState(
                title = "Windows compatibility app",
                description = "Choose the app you use to run Windows games, such as Winlator. RetroPlay will only open it.",
                suggestLabel = "winlator",
            )
        }
        _picker.value = purpose to base
        viewModelScope.launch {
            val apps = launchManager.launchableApps()
            _picker.update { current -> current?.let { it.first to it.second.copy(apps = apps, isLoading = false) } }
        }
    }

    fun dismissPicker() {
        _picker.value = null
    }

    fun onAppPicked(app: InstalledApp) {
        val purpose = _picker.value?.first ?: return
        _picker.value = null
        viewModelScope.launch {
            when (purpose) {
                PickerPurpose.LINK_ANDROID_APP -> gameRepository.setAndroidPackage(gameId, app.packageName)
                PickerPurpose.CHOOSE_EXTERNAL_APP -> preferences.setExternalApp(app.packageName, app.label)
            }
            refresh()
        }
    }

    fun consumeMessage() {
        _message.value = null
    }

    companion object {
        const val GAME_ID_ARG = "gameId"
    }
}
