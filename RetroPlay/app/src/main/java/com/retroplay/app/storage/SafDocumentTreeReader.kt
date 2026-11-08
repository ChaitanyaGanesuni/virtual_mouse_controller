package com.retroplay.app.storage

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.FileNotFoundException
import javax.inject.Inject
import javax.inject.Singleton

/** Storage Access Framework adapter. Uses only read access to folders the user explicitly picked. */
@Singleton
class SafDocumentTreeReader @Inject constructor(
    @ApplicationContext private val context: Context,
) : DocumentTreeReader, PersistedFolderAccess {

    private val resolver: ContentResolver get() = context.contentResolver

    override fun rootDocumentId(treeUri: String): String = DocumentsContract.getTreeDocumentId(Uri.parse(treeUri))

    override fun listChildren(treeUri: String, documentId: String): List<DocumentEntry> = guarded {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(Uri.parse(treeUri), documentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
        )
        resolver.query(children, projection, null, null, null)?.use { c ->
            buildList {
                while (c.moveToNext()) {
                    add(
                        DocumentEntry(
                            documentId = c.getString(0),
                            name = c.getString(1) ?: "",
                            isDirectory = c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR,
                            sizeBytes = if (c.isNull(3)) 0L else c.getLong(3),
                        ),
                    )
                }
            }
        } ?: throw DocumentNotFoundException("The folder is not available.")
    }

    override fun readHeader(treeUri: String, documentId: String, byteCount: Int): ByteArray = guarded {
        val uri = DocumentsContract.buildDocumentUriUsingTree(Uri.parse(treeUri), documentId)
        resolver.openInputStream(uri)?.use { it.readNBytes(byteCount) }
            ?: throw DocumentNotFoundException("The file could not be opened.")
    }

    override fun take(treeUri: String): Result<Unit> = try {
        resolver.takePersistableUriPermission(Uri.parse(treeUri), Intent.FLAG_GRANT_READ_URI_PERMISSION)
        Result.success(Unit)
    } catch (e: SecurityException) {
        Result.failure(e)
    }

    override fun release(treeUri: String) {
        try {
            resolver.releasePersistableUriPermission(Uri.parse(treeUri), Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: SecurityException) {
            // Already released; nothing to do.
        }
    }

    override fun has(treeUri: String): Boolean {
        val uri = Uri.parse(treeUri)
        return resolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission }
    }

    private inline fun <T> guarded(block: () -> T): T = try {
        block()
    } catch (e: SecurityException) {
        throw FolderAccessLostException("Android no longer grants RetroPlay access to this folder.", e)
    } catch (e: FileNotFoundException) {
        throw DocumentNotFoundException(e.message ?: "Not found", e)
    } catch (e: IllegalArgumentException) {
        throw DocumentNotFoundException(e.message ?: "Not found", e)
    }
}
