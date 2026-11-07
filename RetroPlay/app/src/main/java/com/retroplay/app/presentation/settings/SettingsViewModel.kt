package com.retroplay.app.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.retroplay.app.domain.launch.GameLaunchManager
import com.retroplay.app.domain.launch.InstalledApp
import com.retroplay.app.domain.repository.UserPreferences
import com.retroplay.app.domain.repository.UserPreferencesRepository
import com.retroplay.app.presentation.common.AppPickerState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val userPreferencesRepository: UserPreferencesRepository,
    private val launchManager: GameLaunchManager,
) : ViewModel() {

    val preferences: StateFlow<UserPreferences> = userPreferencesRepository.preferences
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), UserPreferences())

    private val _picker = MutableStateFlow<AppPickerState?>(null)
    val picker: StateFlow<AppPickerState?> = _picker.asStateFlow()

    fun setShowReferenceComparison(enabled: Boolean) {
        viewModelScope.launch { userPreferencesRepository.setShowReferenceComparison(enabled) }
    }

    fun showExternalAppPicker() {
        _picker.value = AppPickerState(
            title = "Windows compatibility app",
            description = "Choose the app you use to run Windows games, such as Winlator. RetroPlay will only open it.",
            suggestLabel = "winlator",
        )
        viewModelScope.launch {
            val apps = launchManager.launchableApps()
            _picker.update { it?.copy(apps = apps, isLoading = false) }
        }
    }

    fun dismissPicker() {
        _picker.value = null
    }

    fun onExternalAppPicked(app: InstalledApp) {
        _picker.value = null
        viewModelScope.launch { userPreferencesRepository.setExternalApp(app.packageName, app.label) }
    }

    fun clearExternalApp() {
        viewModelScope.launch { userPreferencesRepository.setExternalApp(null, null) }
    }
}
