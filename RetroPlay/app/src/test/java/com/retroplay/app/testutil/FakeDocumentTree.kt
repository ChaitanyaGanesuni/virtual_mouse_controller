package com.retroplay.app.testutil

import com.retroplay.app.storage.DocumentEntry
import com.retroplay.app.storage.DocumentNotFoundException
import com.retroplay.app.storage.DocumentTreeReader
import com.retroplay.app.storage.FolderAccessLostException
import com.retroplay.app.storage.PersistedFolderAccess

/**
 * In-memory document tree + persisted-permission store. It is strictly read-only, like RetroPlay's
 * real SAF access: there is no API to write, move or delete files, which is what the tests rely on.
 */
class FakeDocumentTree(val treeUri: String = TREE) : DocumentTreeReader, PersistedFolderAccess {

    private data class Node(val entry: DocumentEntry, val header: ByteArray = byteArrayOf())

    private val children = mutableMapOf<String, MutableList<Node>>(ROOT to mutableListOf())
    val granted = mutableSetOf<String>()
    var takeFails = false
    var folderDeleted = false
    var accessRevokedAtProvider = false
    val headerReads = mutableListOf<String>()

    fun addDir(path: String): FakeDocumentTree = apply { ensureDir(path) }

    fun addFile(path: String, size: Long, header: ByteArray = MZ): FakeDocumentTree = apply {
        val parent = path.substringBeforeLast('/', "")
        val parentId = if (parent.isEmpty()) ROOT else ensureDir(parent)
        val name = path.substringAfterLast('/')
        children.getValue(parentId) += Node(DocumentEntry("$ROOT/$path", name, false, size), header)
    }

    fun removeFile(path: String) {
        children.values.forEach { list -> list.removeAll { it.entry.documentId == "$ROOT/$path" } }
    }

    private fun ensureDir(path: String): String {
        var parentId = ROOT
        var current = ""
        for (segment in path.split('/')) {
            current = if (current.isEmpty()) segment else "$current/$segment"
            val id = "$ROOT/$current"
            val list = children.getValue(parentId)
            if (list.none { it.entry.documentId == id }) {
                list += Node(DocumentEntry(id, segment, true, 0))
                children[id] = mutableListOf()
            }
            parentId = id
        }
        return parentId
    }

    override fun rootDocumentId(treeUri: String) = ROOT

    override fun listChildren(treeUri: String, documentId: String): List<DocumentEntry> {
        if (accessRevokedAtProvider) throw FolderAccessLostException("Access revoked")
        if (folderDeleted || treeUri != this.treeUri) throw DocumentNotFoundException("gone")
        return children[documentId]?.map { it.entry } ?: throw DocumentNotFoundException("gone")
    }

    override fun readHeader(treeUri: String, documentId: String, byteCount: Int): ByteArray {
        headerReads += documentId
        val node = children.values.flatten().firstOrNull { it.entry.documentId == documentId }
            ?: throw DocumentNotFoundException("gone")
        return node.header.copyOf(minOf(byteCount, node.header.size))
    }

    override fun take(treeUri: String): Result<Unit> =
        if (takeFails) Result.failure(SecurityException("No persistable permission granted")) else Result.success(Unit).also { granted += treeUri }

    override fun release(treeUri: String) {
        granted -= treeUri
    }

    override fun has(treeUri: String) = treeUri in granted

    companion object {
        const val TREE = "content://com.android.externalstorage.documents/tree/primary%3AGames%2FVice%20City"
        const val TREE_2 = "content://com.android.externalstorage.documents/tree/primary%3AGames%2FOther"
        const val ROOT = "root"
        val MZ = byteArrayOf('M'.code.toByte(), 'Z'.code.toByte(), 0x90.toByte(), 0)
    }
}
