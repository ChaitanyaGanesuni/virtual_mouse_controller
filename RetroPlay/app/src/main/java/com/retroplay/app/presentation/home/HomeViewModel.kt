package com.retroplay.app.presentation.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.retroplay.app.domain.game.GameFilter
import com.retroplay.app.domain.model.Game
import com.retroplay.app.domain.model.GameCategory
import com.retroplay.app.domain.repository.GameRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

data class HomeUiState(
    val isLoading: Boolean = true,
    val recentlyPlayed: List<Game> = emptyList(),
    val favorites: List<Game> = emptyList(),
    val library: List<Game> = emptyList(),
    val categoryCounts: Map<GameCategory, Int> = emptyMap(),
)

@HiltViewModel
class HomeViewModel @Inject constructor(gameRepository: GameRepository) : ViewModel() {
    val uiState: StateFlow<HomeUiState> = gameRepository.observeGames()
        .map { games ->
            HomeUiState(
                isLoading = false,
                recentlyPlayed = GameFilter.recentlyPlayed(games),
                favorites = games.filter { it.isFavorite },
                library = games,
                categoryCounts = GameCategory.entries.associateWith { c -> games.count { it.category == c } },
            )
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), HomeUiState())
}
