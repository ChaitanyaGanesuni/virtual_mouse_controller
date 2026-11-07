package com.retroplay.app.presentation.home

import com.retroplay.app.domain.model.GameCategory
import com.retroplay.app.testutil.FakeGameRepository
import com.retroplay.app.testutil.MainDispatcherRule
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class HomeViewModelTest {
    @get:Rule val mainDispatcherRule = MainDispatcherRule()

    @Test fun summarisesLibrary() = runTest {
        val repo = FakeGameRepository()
        val vm = HomeViewModel(repo)
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.uiState.collect() }

        val state = vm.uiState.value
        assertEquals(6, state.library.size)
        assertTrue(state.recentlyPlayed.isEmpty())
        assertEquals(mapOf(GameCategory.CRICKET to 1, GameCategory.GTA to 5), state.categoryCounts)

        repo.setFavorite("gta-iv", true)
        assertEquals(listOf("gta-iv"), vm.uiState.value.favorites.map { it.id })
    }
}
