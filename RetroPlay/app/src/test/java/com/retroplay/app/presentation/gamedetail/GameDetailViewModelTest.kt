package com.retroplay.app.presentation.gamedetail

import androidx.lifecycle.SavedStateHandle
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
class GameDetailViewModelTest {
    @get:Rule val mainDispatcherRule = MainDispatcherRule()

    private fun vm(id: String, repo: FakeGameRepository = FakeGameRepository()) =
        GameDetailViewModel(SavedStateHandle(mapOf(GameDetailViewModel.GAME_ID_ARG to id)), repo)

    @Test fun loadsGameAndUpdatesFavouriteAndNotes() = runTest {
        val vm = vm("ea-sports-cricket-07")
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.uiState.collect() }

        val ready = vm.uiState.value as GameDetailUiState.Ready
        assertEquals("EA Sports Cricket 07", ready.game.title)

        vm.setFavorite(true)
        assertTrue((vm.uiState.value as GameDetailUiState.Ready).game.isFavorite)

        vm.saveNotes("Needs 1280x720 ")
        assertEquals("Needs 1280x720", (vm.uiState.value as GameDetailUiState.Ready).game.userNotes)
    }

    @Test fun unknownIdIsNotFound() = runTest {
        val vm = vm("missing")
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.uiState.collect() }
        assertEquals(GameDetailUiState.NotFound, vm.uiState.value)
    }
}
