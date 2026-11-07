package com.retroplay.app.presentation.library

import com.retroplay.app.domain.model.GameCategory
import com.retroplay.app.testutil.FakeGameRepository
import com.retroplay.app.testutil.MainDispatcherRule
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class LibraryViewModelTest {
    @get:Rule val mainDispatcherRule = MainDispatcherRule()

    @Test fun searchAndCategoryFilterTheLibrary() = runTest {
        val vm = LibraryViewModel(FakeGameRepository())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.uiState.collect() }

        assertEquals(9, vm.uiState.value.games.size)
        vm.onCategorySelected(GameCategory.GTA)
        assertEquals(8, vm.uiState.value.games.size)
        vm.onQueryChange("andreas")
        assertEquals(listOf("gta-san-andreas", "gta-san-andreas-android"), vm.uiState.value.games.map { it.id })
        assertEquals(9, vm.uiState.value.totalCount)
        vm.onCategorySelected(null)
        vm.onQueryChange("")
        assertEquals(9, vm.uiState.value.games.size)
    }
}
