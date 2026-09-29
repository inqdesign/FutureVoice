package com.roro.futurevoice.data

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.provider.OpenableColumns
import com.roro.futurevoice.R
import com.roro.futurevoice.talk.ScenarioBrief
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

/**
 * The bytes of a file the learner attached to a situation, held in MEMORY
 * only until the reading that uses them has run (iOS `BriefAttachmentCache`).
 * The composer reads the file once, at the pick, and parks it here by source
 * id so the reading — which runs a screen later, on the scene — never has to
 * reopen it. Nothing is written to disk; a miss falls back to the source's
 * content URI.
 */
object BriefAttachmentCache {
    private val bytes = HashMap<String, Pair<ByteArray, String>>()

    @Synchronized fun put(id: String, data: ByteArray, mime: String) { bytes[id] = data to mime }
    @Synchronized fun take(id: String): Pair<ByteArray, String>? = bytes[id]
    @Synchronized fun drop(id: String) { bytes.remove(id) }
}

/**
 * Reads an attached file WHERE IT LIVES (iOS `ScenarioAttachmentReader`).
 * The document picker hands over a `content://` URI; the bytes come out, a
 * persistable READ grant is kept on the URI for "Read again", and nothing is
 * copied into the app's own storage — ever.
 */
object ScenarioAttachmentReader {
    /** The inline ceiling a Gemini request carries comfortably (iOS
     *  `GeminiClient.maxInlineBytes`): 10 MB of file bytes leaves room for
     *  base64 growth and the prompt inside the API's 20 MB. */
    const val MAX_BYTES = 10 * 1024 * 1024
    const val MAX_MB = MAX_BYTES / (1024 * 1024)

    /** What the picker offers. Anything else is refused with a message
     *  rather than uploaded and ignored. */
    val pickerTypes = arrayOf("application/pdf", "image/*", "text/plain", "text/*")

    sealed class ReadError : Exception() {
        data class TooLarge(val mb: Int) : ReadError()
        data class Unsupported(val ext: String) : ReadError()
        data object Unreadable : ReadError()
        data object Stale : ReadError()

        fun describe(context: Context): String = when (this) {
            is TooLarge -> context.getString(R.string.that_file_is_over_lld_mb_pick_a_smaller_one, mb)
            is Unsupported -> context.getString(R.string.can_t_read_files_yet_pdf_images_and_plain_text_work, ext)
            Unreadable -> context.getString(R.string.couldn_t_open_that_file)
            Stale -> context.getString(R.string.that_file_moved_or_was_deleted_pick_it_again)
        }
    }

    class Read(val source: ScenarioBrief.Source, val data: ByteArray, val mime: String)

    /** A file the picker just handed over. Keeps a persistable read grant so
     *  "Read again" can open the same file later without a copy. */
    suspend fun read(context: Context, uri: Uri): Read = withContext(Dispatchers.IO) {
        runCatching {
            context.contentResolver.takePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val name = displayName(context, uri) ?: uri.lastPathSegment ?: "file"
        val (data, mime) = bytes(context, uri, name)
        val kind = if (mime.startsWith("image/")) ScenarioBrief.Kind.IMAGE else ScenarioBrief.Kind.FILE
        Read(ScenarioBrief.Source(kind = kind, label = name, androidUri = uri.toString()), data, mime)
    }

    /** Reopen a file from the URI a previous pick left behind. */
    suspend fun reread(context: Context, uriString: String, label: String): Pair<ByteArray, String> =
        withContext(Dispatchers.IO) {
            val uri = runCatching { Uri.parse(uriString) }.getOrNull() ?: throw ReadError.Stale
            try {
                bytes(context, uri, label)
            } catch (e: ReadError) {
                throw if (e is ReadError.Unreadable) ReadError.Stale else e
            } catch (e: SecurityException) {
                throw ReadError.Stale
            }
        }

    /** A photo from the camera: re-encoded as a bounded JPEG, which also
     *  drops EXIF and location. Nothing to reopen later, so no URI. */
    fun read(image: Bitmap, label: String): Read? {
        val jpeg = jpeg(image) ?: return null
        return Read(ScenarioBrief.Source(kind = ScenarioBrief.Kind.IMAGE, label = label), jpeg, "image/jpeg")
    }

    private fun displayName(context: Context, uri: Uri): String? = runCatching {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
    }.getOrNull()

    private fun bytes(context: Context, uri: Uri, name: String): Pair<ByteArray, String> {
        val resolver = context.contentResolver
        val ext = name.substringAfterLast('.', "").lowercase()
        val mime = resolver.getType(uri) ?: when (ext) {
            "pdf" -> "application/pdf"
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "heic", "heif" -> "image/heic"
            "webp" -> "image/webp"
            "txt", "md", "csv" -> "text/plain"
            else -> "application/octet-stream"
        }
        val kind = when {
            mime == "application/pdf" -> "pdf"
            mime.startsWith("image/") -> "image"
            mime.startsWith("text/") -> "text"
            else -> throw ReadError.Unsupported(ext.ifEmpty { "?" })
        }
        val data = try {
            resolver.openInputStream(uri)?.use { input ->
                val out = ByteArrayOutputStream()
                val buf = ByteArray(64 * 1024)
                var total = 0
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    total += n
                    if (total > MAX_BYTES) throw ReadError.TooLarge(MAX_MB)
                    out.write(buf, 0, n)
                }
                out.toByteArray()
            } ?: throw ReadError.Unreadable
        } catch (e: ReadError) {
            throw e
        } catch (e: SecurityException) {
            throw ReadError.Stale
        } catch (e: Exception) {
            throw ReadError.Unreadable
        }
        return when (kind) {
            // HEIC and friends are not on Gemini's list; a JPEG always is.
            "image" -> {
                val decoded = BitmapFactory.decodeByteArray(data, 0, data.size) ?: throw ReadError.Unreadable
                val upright = rotated(decoded, orientation(data))
                (jpeg(upright) ?: throw ReadError.Unreadable) to "image/jpeg"
            }
            "pdf" -> data to "application/pdf"
            else -> data to "text/plain"
        }
    }

    private fun orientation(data: ByteArray): Int = runCatching {
        ExifInterface(data.inputStream()).getAttributeInt(
            ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
    }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)

    private fun rotated(bitmap: Bitmap, orientation: Int): Bitmap {
        val degrees = when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> return bitmap
        }
        val m = Matrix().apply { postRotate(degrees) }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, m, true)
    }

    /** Long edge ≤ 1600 px, JPEG 85 — a fresh bitmap, so no metadata rides along. */
    private fun jpeg(source: Bitmap): ByteArray? = runCatching {
        val longest = maxOf(source.width, source.height).coerceAtLeast(1)
        val scale = minOf(1f, 1600f / longest)
        val sized = if (scale < 1f) Bitmap.createScaledBitmap(
            source, (source.width * scale).toInt().coerceAtLeast(1),
            (source.height * scale).toInt().coerceAtLeast(1), true) else source
        ByteArrayOutputStream().use { out ->
            sized.compress(Bitmap.CompressFormat.JPEG, 85, out)
            out.toByteArray()
        }
    }.getOrNull()
}
