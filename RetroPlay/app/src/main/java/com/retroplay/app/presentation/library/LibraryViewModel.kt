package com.retroplay.app.presentation.library

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.retroplay.app.domain.game.GameFilter
import com.retroplay.app.domain.model.Game
import com.retroplay.app.domain.model.GameCategory
import com.retroplay.app.domain.repository.GameRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

data class LibraryUiState(
    val isLoading: Boolean = true,
    val query: String = "",
    val selectedCategory: GameCategory? = null,
    val games: List<Game> = emptyList(),
    val totalCount: Int = 0,
)

@HiltViewModel
class LibraryViewModel @Inject constructor(gameRepository: GameRepository) : ViewModel() {

    private val query = MutableStateFlow("")
    private val category = MutableStateFlow<GameCategory?>(null)

    val uiState: StateFlow<LibraryUiState> =
        combine(gameRepository.observeGames(), query, category) { games, q, c ->
            LibraryUiState(
                isLoading = false,
                query = q,
                selectedCategory = c,
                games = GameFilter.apply(games, q, c),
                totalCount = games.size,
            )
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), LibraryUiState())

    fun onQueryChange(value: String) {
        query.value = value
    }

    fun onCategorySelected(value: GameCategory?) {
        category.value = value
    }
}
