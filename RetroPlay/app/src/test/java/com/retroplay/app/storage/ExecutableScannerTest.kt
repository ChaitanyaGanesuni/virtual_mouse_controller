package com.retroplay.app.storage

import com.retroplay.app.testutil.FakeDocumentTree
import com.retroplay.app.testutil.FakeDocumentTree.Companion.TREE
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ExecutableScannerTest {

    @Test fun findsExecutablesShallowFirstCaseInsensitively() {
        val tree = FakeDocumentTree()
            .addFile("readme.txt", 10)
            .addFile("gta-vc.exe", 3_000_000)
            .addFile("Mss/setup.EXE", 500)
            .addFile("data/maps/map.dat", 99)
        val result = ExecutableScanner(tree).scan(TREE)
        assertEquals(listOf("gta-vc.exe", "Mss/setup.EXE"), result.candidates.map { it.relativePath })
        assertEquals(3_000_000L, result.candidates.first().sizeBytes)
        assertFalse(result.truncated)
    }

    @Test fun depthLimitMarksResultTruncated() {
        val tree = FakeDocumentTree().addFile("a/b/c/deep.exe", 1).addFile("top.exe", 1)
        val result = ExecutableScanner(tree).scan(TREE, maxDepth = 1)
        assertEquals(listOf("top.exe"), result.candidates.map { it.relativePath })
        assertTrue(result.truncated)
    }

    @Test fun entryLimitStopsLargeFolders() {
        val tree = FakeDocumentTree()
        repeat(50) { tree.addFile("file$it.dat", 1) }
        val result = ExecutableScanner(tree).scan(TREE, maxEntries = 10)
        assertEquals(10, result.entriesVisited)
        assertTrue(result.truncated)
    }
}
