package com.retroplay.app.storage

/** A file or folder inside a user-granted document tree. */
data class DocumentEntry(
    val documentId: String,
    val name: String,
    val isDirectory: Boolean,
    val sizeBytes: Long,
)

/** Thrown when Android no longer grants access to a folder. */
class FolderAccessLostException(message: String, cause: Throwable? = null) : Exception(message, cause)

/** Thrown when a folder or file can no longer be found. */
class DocumentNotFoundException(message: String, cause: Throwable? = null) : Exception(message, cause)

/**
 * Read-only access to a Storage Access Framework document tree. URIs are passed as strings so the
 * scanning and validation logic stays plain Kotlin and testable.
 */
interface DocumentTreeReader {
    fun rootDocumentId(treeUri: String): String
    /** @throws FolderAccessLostException or DocumentNotFoundException */
    fun listChildren(treeUri: String, documentId: String): List<DocumentEntry>
    /** Reads up to [byteCount] bytes from the start of a file, never more. */
    fun readHeader(treeUri: String, documentId: String, byteCount: Int): ByteArray
}

/** Persisted (survives restarts) read access to user-selected folders. No runtime permission is involved. */
interface PersistedFolderAccess {
    fun take(treeUri: String): Result<Unit>
    fun release(treeUri: String)
    fun has(treeUri: String): Boolean
}
