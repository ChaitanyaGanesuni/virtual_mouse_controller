package com.retroplay.app.presentation.favorites

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
class FavoritesViewModelTest {
    @get:Rule val mainDispatcherRule = MainDispatcherRule()

    @Test fun showsOnlyFavouritesAndCanRemoveThem() = runTest {
        val repo = FakeGameRepository()
        val vm = FavoritesViewModel(repo)
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.uiState.collect() }

        assertTrue(vm.uiState.value.games.isEmpty())
        repo.setFavorite("gta-v", true)
        assertEquals(listOf("gta-v"), vm.uiState.value.games.map { it.id })
        vm.removeFavorite("gta-v")
        assertTrue(vm.uiState.value.games.isEmpty())
    }
}
