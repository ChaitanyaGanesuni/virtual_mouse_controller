package com.retroplay.app.presentation.gamefiles

import androidx.lifecycle.SavedStateHandle
import com.retroplay.app.domain.model.GameCategory
import com.retroplay.app.domain.model.ImportValidity
import com.retroplay.app.presentation.gamedetail.GameDetailViewModel
import com.retroplay.app.storage.ExecutableScanner
import com.retroplay.app.storage.ExecutableValidator
import com.retroplay.app.storage.GameImportManager
import com.retroplay.app.testutil.FakeDocumentTree
import com.retroplay.app.testutil.FakeDocumentTree.Companion.TREE
import com.retroplay.app.testutil.FakeGameRepository
import com.retroplay.app.testutil.FakeInstallationRepository
import com.retroplay.app.testutil.MainDispatcherRule
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class GameFilesViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private val tree = FakeDocumentTree().addFile("gta-vc.exe", 3_000_000).addFile("Mss/run.exe", 10)
    private val games = FakeGameRepository()
    private val installs = FakeInstallationRepository()
    private val manager = GameImportManager(
        tree, ExecutableScanner(tree), ExecutableValidator(tree, tree), games, installs, { 1L }, main.dispatcher,
    )

    private fun vm(id: String = "gta-vice-city") =
        GameFilesViewModel(SavedStateHandle(mapOf(GameDetailViewModel.GAME_ID_ARG to id)), installs, manager)

    @Test fun fullImportFlow() = runTest {
        val vm = vm()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.installation.collect() }

        vm.onFolderPicked(null) // user cancelled the system picker
        assertEquals(ImportFlowState.Idle, vm.flow.value)

        vm.onFolderPicked(TREE)
        val choose = vm.flow.value as ImportFlowState.ChooseExecutable
        assertEquals(2, choose.candidates.size)

        vm.onExecutableChosen(choose.candidates.first())
        assertTrue(vm.flow.value is ImportFlowState.Done)
        assertEquals(ImportValidity.VALID, vm.installation.value!!.validity)

        vm.dismissResult()
        assertEquals(ImportFlowState.Idle, vm.flow.value)
    }

    @Test fun errorsAreReported() = runTest {
        tree.takeFails = true
        val vm = vm()
        vm.onFolderPicked(TREE)
        assertTrue((vm.flow.value as ImportFlowState.Error).message.contains("keep access"))
    }

    @Test fun cancelReleasesAccess() = runTest {
        val vm = vm()
        vm.onFolderPicked(TREE)
        vm.cancelFlow()
        assertEquals(ImportFlowState.Idle, vm.flow.value)
        assertFalse(tree.has(TREE))
    }

    @Test fun removeImportAndRemoveCustomGame() = runTest {
        val custom = games.registerCustomGame("My Game", GameCategory.OTHER)
        val vm = vm(custom.id)
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.installation.collect() }
        vm.onFolderPicked(TREE)
        vm.onExecutableChosen((vm.flow.value as ImportFlowState.ChooseExecutable).candidates.first())

        vm.removeImport()
        assertNull(vm.installation.value)

        vm.removeCustomGame()
        assertTrue(vm.removed.value)
    }
}
