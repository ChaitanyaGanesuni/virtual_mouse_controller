package com.retroplay.app.storage

import com.retroplay.app.domain.model.ImportValidity
import com.retroplay.app.testutil.FakeDocumentTree
import com.retroplay.app.testutil.FakeDocumentTree.Companion.TREE
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ExecutableValidatorTest {

    private fun tree() = FakeDocumentTree().apply { granted += TREE }
        .addFile("gta-vc.exe", 3_000_000)
        .addFile("Bin/Game.exe", 10)
        .addFile("empty.exe", 0)
        .addFile("fake.exe", 100, header = "PK".toByteArray())

    private fun validity(tree: FakeDocumentTree, path: String) =
        (ExecutableValidator(tree, tree).validate(TREE, path) as? ValidationOutcome.Invalid)?.validity

    @Test fun validExecutableReportsSizeAndReadsOnlyTheHeader() {
        val tree = tree()
        assertEquals(ValidationOutcome.Valid(3_000_000), ExecutableValidator(tree, tree).validate(TREE, "gta-vc.exe"))
        assertEquals(1, tree.headerReads.size)
    }

    @Test fun pathMatchingIsCaseInsensitiveLikeWindows() {
        val tree = tree()
        assertTrue(ExecutableValidator(tree, tree).validate(TREE, "bin/game.EXE") is ValidationOutcome.Valid)
    }

    @Test fun lostPermissionIsDetectedBeforeReading() {
        val tree = tree().apply { granted.clear() }
        assertEquals(ImportValidity.PERMISSION_LOST, validity(tree, "gta-vc.exe"))
        assertTrue(tree.headerReads.isEmpty())
    }

    @Test fun providerRevokingAccessIsPermissionLost() {
        val tree = tree().apply { accessRevokedAtProvider = true }
        assertEquals(ImportValidity.PERMISSION_LOST, validity(tree, "gta-vc.exe"))
    }

    @Test fun deletedFolderAndMissingFile() {
        assertEquals(ImportValidity.FOLDER_MISSING, validity(tree().apply { folderDeleted = true }, "gta-vc.exe"))
        assertEquals(ImportValidity.EXECUTABLE_MISSING, validity(tree(), "missing.exe"))
        assertEquals(ImportValidity.EXECUTABLE_MISSING, validity(tree(), "gta-vc.exe/inner.exe"))
    }

    @Test fun rejectsNonExecutables() {
        assertEquals(ImportValidity.INVALID_EXECUTABLE, validity(tree(), "empty.exe"))
        assertEquals(ImportValidity.INVALID_EXECUTABLE, validity(tree(), "fake.exe"))
        assertEquals(ImportValidity.INVALID_EXECUTABLE, validity(tree().addFile("notes.txt", 5), "notes.txt"))
    }

    @Test fun headerCheck() {
        assertTrue(ExecutableValidator.isWindowsExecutable(FakeDocumentTree.MZ))
        assertTrue(!ExecutableValidator.isWindowsExecutable(byteArrayOf('M'.code.toByte())))
    }
}
