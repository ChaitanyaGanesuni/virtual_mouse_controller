package com.retroplay.app.presentation.gamefiles

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.retroplay.app.domain.model.GameInstallation
import com.retroplay.app.domain.repository.InstallationRepository
import com.retroplay.app.presentation.gamedetail.GameDetailViewModel
import com.retroplay.app.storage.ExecutableCandidate
import com.retroplay.app.storage.GameImportManager
import com.retroplay.app.storage.ImportOutcome
import com.retroplay.app.storage.ScanStep
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/** Progress of the Storage Access Framework import flow. */
sealed interface ImportFlowState {
    data object Idle : ImportFlowState
    data object Scanning : ImportFlowState
    data class ChooseExecutable(
        val treeUri: String,
        val folderDisplayPath: String,
        val candidates: List<ExecutableCandidate>,
        val truncated: Boolean,
    ) : ImportFlowState
    data object Validating : ImportFlowState
    data class Done(val installation: GameInstallation) : ImportFlowState
    data class Error(val message: String) : ImportFlowState
}

@HiltViewModel
class GameFilesViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    installations: InstallationRepository,
    private val importManager: GameImportManager,
) : ViewModel() {

    private val gameId: String = checkNotNull(savedStateHandle[GameDetailViewModel.GAME_ID_ARG])

    val installation: StateFlow<GameInstallation?> = installations.observe(gameId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    private val _flow = MutableStateFlow<ImportFlowState>(ImportFlowState.Idle)
    val flow: StateFlow<ImportFlowState> = _flow.asStateFlow()

    private val _removed = MutableStateFlow(false)
    /** True once a custom game has been removed, so the screen can close. */
    val removed: StateFlow<Boolean> = _removed.asStateFlow()

    /** Called with the folder URI returned by the system folder picker (null when the user cancelled). */
    fun onFolderPicked(treeUri: String?) {
        if (treeUri == null) return
        _flow.value = ImportFlowState.Scanning
        viewModelScope.launch {
            _flow.value = when (val step = importManager.scanFolder(gameId, treeUri)) {
                is ScanStep.Failed -> ImportFlowState.Error(step.message)
                is ScanStep.Found -> ImportFlowState.ChooseExecutable(
                    step.treeUri, step.folderDisplayPath, step.result.candidates, step.result.truncated,
                )
            }
        }
    }

    fun onExecutableChosen(candidate: ExecutableCandidate) {
        val choose = _flow.value as? ImportFlowState.ChooseExecutable ?: return
        _flow.value = ImportFlowState.Validating
        viewModelScope.launch {
            _flow.value = when (val outcome = importManager.completeImport(gameId, choose.treeUri, candidate)) {
                is ImportOutcome.Imported -> ImportFlowState.Done(outcome.installation)
                is ImportOutcome.Failed -> ImportFlowState.Error(outcome.message)
            }
        }
    }

    fun cancelFlow() {
        val choose = _flow.value as? ImportFlowState.ChooseExecutable
        _flow.value = ImportFlowState.Idle
        if (choose != null) viewModelScope.launch { importManager.cancelImport(gameId, choose.treeUri) }
    }

    fun dismissResult() {
        _flow.value = ImportFlowState.Idle
    }

    fun revalidate() {
        viewModelScope.launch { importManager.revalidate(gameId) }
    }

    fun removeImport() {
        viewModelScope.launch { importManager.removeImport(gameId) }
    }

    fun removeCustomGame() {
        viewModelScope.launch { _removed.value = importManager.removeCustomGame(gameId) }
    }
}
