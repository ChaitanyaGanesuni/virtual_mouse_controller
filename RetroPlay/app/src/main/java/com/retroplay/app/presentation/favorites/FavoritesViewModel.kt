package com.retroplay.app.presentation.favorites

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

data class FavoritesUiState(val isLoading: Boolean = true, val games: List<Game> = emptyList())

@HiltViewModel
class FavoritesViewModel @Inject constructor(
    private val gameRepository: GameRepository,
) : ViewModel() {
    val uiState: StateFlow<FavoritesUiState> = gameRepository.observeGames()
        .map { games -> FavoritesUiState(isLoading = false, games = games.filter { it.isFavorite }) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), FavoritesUiState())

    fun removeFavorite(id: String) {
        viewModelScope.launch { gameRepository.setFavorite(id, false) }
    }
}
