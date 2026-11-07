package com.retroplay.app.presentation.gamedetail

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.retroplay.app.domain.model.Game
import com.retroplay.app.domain.repository.GameRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface GameDetailUiState {
    data object Loading : GameDetailUiState
    data object NotFound : GameDetailUiState
    data class Ready(val game: Game) : GameDetailUiState
}

@HiltViewModel
class GameDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val gameRepository: GameRepository,
) : ViewModel() {

    /** Matches the `gameId` property of the type-safe GameDetailRoute. */
    private val gameId: String = checkNotNull(savedStateHandle[GAME_ID_ARG]) { "gameId argument missing" }

    val uiState: StateFlow<GameDetailUiState> = gameRepository.observeGame(gameId)
        .map { game -> if (game == null) GameDetailUiState.NotFound else GameDetailUiState.Ready(game) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), GameDetailUiState.Loading)

    fun setFavorite(favorite: Boolean) {
        viewModelScope.launch { gameRepository.setFavorite(gameId, favorite) }
    }

    fun saveNotes(notes: String) {
        viewModelScope.launch { gameRepository.updateNotes(gameId, notes) }
    }

    companion object {
        const val GAME_ID_ARG = "gameId"
    }
}
