package com.retroplay.app.storage

import com.retroplay.app.domain.model.GameCategory
import com.retroplay.app.domain.model.ImportValidity
import com.retroplay.app.domain.model.InstallationStatus
import com.retroplay.app.testutil.FakeDocumentTree
import com.retroplay.app.testutil.FakeDocumentTree.Companion.TREE
import com.retroplay.app.testutil.FakeDocumentTree.Companion.TREE_2
import com.retroplay.app.testutil.FakeGameRepository
import com.retroplay.app.testutil.FakeInstallationRepository
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GameImportManagerTest {

    private class Env(scope: TestScope, val tree: FakeDocumentTree = FakeDocumentTree().addFile("gta-vc.exe", 3_000_000).addFile("Mss/run.exe", 10)) {
        val games = FakeGameRepository()
        val installs = FakeInstallationRepository()
        val manager = GameImportManager(
            tree, ExecutableScanner(tree), ExecutableValidator(tree, tree), games, installs, { 42L },
            StandardTestDispatcher(scope.testScheduler),
        )
        suspend fun status(id: String) = games.observeGame(id).first()!!.installationStatus
        suspend fun importVc(gameId: String = "gta-vice-city", uri: String = TREE): ImportOutcome {
            val found = manager.scanFolder(gameId, uri) as ScanStep.Found
            return manager.completeImport(gameId, uri, found.result.candidates.first())
        }
    }

    @Test fun scanKeepsFolderAccessAndListsExecutables() = runTest {
        val env = Env(this)
        val step = env.manager.scanFolder("gta-vice-city", TREE) as ScanStep.Found
        assertEquals("Internal storage/Games/Vice City", step.folderDisplayPath)
        assertEquals(listOf("gta-vc.exe", "Mss/run.exe"), step.result.candidates.map { it.relativePath })
        assertTrue(env.tree.has(TREE))
    }

    @Test fun refusedPermissionFailsWithoutStoringAnything() = runTest {
        val env = Env(this).apply { tree.takeFails = true }
        val step = env.manager.scanFolder("gta-vice-city", TREE) as ScanStep.Failed
        assertTrue(step.message.contains("did not let RetroPlay keep access"))
        assertTrue(env.installs.items.value.isEmpty())
    }

    @Test fun folderWithoutExecutablesFailsAndReleasesAccess() = runTest {
        val env = Env(this, FakeDocumentTree().addFile("readme.txt", 1))
        val step = env.manager.scanFolder("gta-vice-city", TREE) as ScanStep.Failed
        assertTrue(step.message.startsWith("No .exe files were found in Internal storage/Games/Vice City"))
        assertFalse(env.tree.has(TREE))
    }

    @Test fun completingImportStoresReferenceAndMarksGameImported() = runTest {
        val env = Env(this)
        val installation = (env.importVc() as ImportOutcome.Imported).installation
        assertEquals("gta-vc.exe", installation.executableRelativePath)
        assertEquals(ImportValidity.VALID, installation.validity)
        assertEquals(42L, installation.importedAtEpochMillis)
        assertEquals(installation, env.installs.get("gta-vice-city"))
        assertEquals(InstallationStatus.IMPORTED, env.status("gta-vice-city"))
    }

    @Test fun invalidExecutableIsReportedAndAccessReleased() = runTest {
        val env = Env(this, FakeDocumentTree().addFile("bad.exe", 5, header = "XX".toByteArray()))
        val found = env.manager.scanFolder("gta-vice-city", TREE) as ScanStep.Found
        val outcome = env.manager.completeImport("gta-vice-city", TREE, found.result.candidates.single())
        assertTrue((outcome as ImportOutcome.Failed).message.contains("MZ"))
        assertNull(env.installs.get("gta-vice-city"))
        assertFalse(env.tree.has(TREE))
    }

    @Test fun cancellingAfterScanReleasesUnusedAccess() = runTest {
        val env = Env(this)
        env.manager.scanFolder("gta-vice-city", TREE)
        env.manager.cancelImport("gta-vice-city", TREE)
        assertFalse(env.tree.has(TREE))
    }

    @Test fun revalidationTracksMissingAndRestoredFiles() = runTest {
        val env = Env(this)
        env.importVc()
        env.tree.removeFile("gta-vc.exe")
        assertEquals(ImportValidity.EXECUTABLE_MISSING, env.manager.revalidate("gta-vice-city")!!.validity)
        assertEquals(InstallationStatus.MISSING, env.status("gta-vice-city"))

        env.tree.addFile("gta-vc.exe", 3_000_001)
        val ok = env.manager.revalidate("gta-vice-city")!!
        assertEquals(ImportValidity.VALID, ok.validity)
        assertEquals(3_000_001L, ok.executableSizeBytes)
        assertEquals(InstallationStatus.IMPORTED, env.status("gta-vice-city"))
    }

    @Test fun revokedAccessIsReportedOnRevalidation() = runTest {
        val env = Env(this)
        env.importVc()
        env.tree.granted.clear()
        assertEquals(ImportValidity.PERMISSION_LOST, env.manager.revalidate("gta-vice-city")!!.validity)
    }

    @Test fun removingImportForgetsReferenceButNeverTouchesFiles() = runTest {
        val env = Env(this)
        env.importVc()
        env.manager.removeImport("gta-vice-city")
        assertNull(env.installs.get("gta-vice-city"))
        assertEquals(InstallationStatus.NOT_IMPORTED, env.status("gta-vice-city"))
        assertFalse(env.tree.has(TREE))
        // The files are still there.
        assertEquals(2, ExecutableScanner(env.tree).scan(TREE).candidates.size)
    }

    @Test fun sharedFolderStaysAccessibleWhileAnotherGameUsesIt() = runTest {
        val env = Env(this)
        env.importVc("gta-vice-city")
        env.importVc("gta-iii")
        env.manager.removeImport("gta-vice-city")
        assertTrue(env.tree.has(TREE))
        env.manager.removeImport("gta-iii")
        assertFalse(env.tree.has(TREE))
    }

    @Test fun reimportingFromAnotherFolderReleasesTheOldOne() = runTest {
        val tree = FakeDocumentTree(TREE).addFile("gta-vc.exe", 1)
        val env = Env(this, tree)
        env.importVc()
        // Simulate picking a second folder (same fake contents, different URI) via a second tree.
        val tree2 = FakeDocumentTree(TREE_2).addFile("gta-vc.exe", 2)
        val manager2 = GameImportManager(
            tree2, ExecutableScanner(tree2), ExecutableValidator(tree2, tree2), env.games, env.installs, { 43L },
            StandardTestDispatcher(testScheduler),
        )
        tree2.granted += TREE // the old grant, as Android would still hold it
        val found = manager2.scanFolder("gta-vice-city", TREE_2) as ScanStep.Found
        manager2.completeImport("gta-vice-city", TREE_2, found.result.candidates.single())
        assertEquals(TREE_2, env.installs.get("gta-vice-city")!!.folderUri)
        assertFalse(tree2.has(TREE))
    }

    @Test fun customGamesCanBeRemovedCatalogueGamesCannot() = runTest {
        val env = Env(this)
        val custom = env.games.registerCustomGame("Midtown Classic", GameCategory.OTHER)
        env.importVc(custom.id)
        assertTrue(env.manager.removeCustomGame(custom.id))
        assertNull(env.games.observeGame(custom.id).first())
        assertFalse(env.manager.removeCustomGame("gta-iii"))
        assertTrue(env.games.observeGame("gta-iii").first() != null)
    }
}
