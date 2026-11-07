package com.retroplay.app.presentation.discover

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.retroplay.app.domain.model.CompatibilityStatus
import com.retroplay.app.domain.model.Game
import com.retroplay.app.domain.model.GameCategory
import com.retroplay.app.domain.repository.GameRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

data class DiscoverCollection(val title: String, val subtitle: String, val games: List<Game>)

data class DiscoverUiState(
    val isLoading: Boolean = true,
    val collections: List<DiscoverCollection> = emptyList(),
)

@HiltViewModel
class DiscoverViewModel @Inject constructor(gameRepository: GameRepository) : ViewModel() {
    val uiState: StateFlow<DiscoverUiState> = gameRepository.observeGames()
        .map { games -> DiscoverUiState(isLoading = false, collections = collectionsFor(games)) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DiscoverUiState())

    companion object {
        /** Builds browse collections; empty collections are omitted. */
        fun collectionsFor(games: List<Game>): List<DiscoverCollection> = listOf(
            DiscoverCollection(
                "Grand Theft Auto",
                "The open-world series, PC editions",
                games.filter { it.category == GameCategory.GTA }.sortedBy { it.releaseYear ?: Int.MAX_VALUE },
            ),
            DiscoverCollection(
                "Cricket",
                "Classic cricket simulations",
                games.filter { it.category == GameCategory.CRICKET },
            ),
            DiscoverCollection(
                "2000s PC classics",
                "PC editions released 2000–2009",
                games.filter { (it.releaseYear ?: 0) in 2000..2009 },
            ),
            DiscoverCollection(
                "Awaiting a compatibility test",
                "No test recorded on this device yet",
                games.filter { it.compatibilityStatus == CompatibilityStatus.NOT_TESTED },
            ),
        ).filter { it.games.isNotEmpty() }
    }
}
