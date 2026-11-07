package com.retroplay.app.presentation.compatibility

import com.retroplay.app.domain.model.CompatibilityStatus
import com.retroplay.app.testutil.FakeDeviceProfileManager
import com.retroplay.app.testutil.FakeGameRepository
import com.retroplay.app.testutil.MainDispatcherRule
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CompatibilityReportViewModelTest {
    @get:Rule val mainDispatcherRule = MainDispatcherRule()

    @Test fun countsStatusesAndSummarisesDevice() = runTest {
        val vm = CompatibilityReportViewModel(FakeGameRepository(), FakeDeviceProfileManager())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.uiState.collect() }

        val state = vm.uiState.value
        assertEquals(9, state.statusCounts[CompatibilityStatus.NOT_TESTED])
        assertEquals(0, state.statusCounts[CompatibilityStatus.PLAYABLE])
        assertEquals(0, state.testedCount)
        assertEquals("Google Pixel 9", state.device?.model)
        assertEquals("Mali-G715", state.device?.gpu)
    }

    @Test fun deviceFailureLeavesSummaryEmptyButListsGames() = runTest {
        val vm = CompatibilityReportViewModel(
            FakeGameRepository(),
            FakeDeviceProfileManager(failure = IllegalStateException("x")),
        )
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.uiState.collect() }
        assertNull(vm.uiState.value.device)
        assertEquals(9, vm.uiState.value.games.size)
    }
}
