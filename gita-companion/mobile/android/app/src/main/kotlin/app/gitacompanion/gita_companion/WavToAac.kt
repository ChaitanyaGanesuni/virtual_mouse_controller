package app.gitacompanion.gita_companion

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Converts a 16-bit PCM WAV file (what Android's text-to-speech writes) to
 * AAC-LC in an .m4a file with the platform encoder (MediaCodec + MediaMuxer):
 * no extra libraries. Anything unexpected throws, and the caller keeps the
 * WAV.
 */
object WavToAac {
    private const val TIMEOUT_US = 10_000L

    private class Wav(val sampleRate: Int, val channels: Int, val dataOffset: Long, val dataSize: Long)

    private fun readHeader(file: RandomAccessFile): Wav {
        val riff = ByteArray(12)
        file.readFully(riff)
        if (String(riff, 0, 4, Charsets.US_ASCII) != "RIFF" || String(riff, 8, 4, Charsets.US_ASCII) != "WAVE") {
            throw IllegalArgumentException("not a WAV file")
        }
        var sampleRate = 0
        var channels = 0
        var bits = 0
        var format = 0
        val chunk = ByteArray(8)
        while (file.filePointer + 8 <= file.length()) {
            file.readFully(chunk)
            val id = String(chunk, 0, 4, Charsets.US_ASCII)
            val size = ByteBuffer.wrap(chunk, 4, 4).order(ByteOrder.LITTLE_ENDIAN).int.toLong() and 0xffffffffL
            when (id) {
                "fmt " -> {
                    val fmt = ByteArray(size.toInt())
                    file.readFully(fmt)
                    val b = ByteBuffer.wrap(fmt).order(ByteOrder.LITTLE_ENDIAN)
                    format = b.getShort(0).toInt()
                    channels = b.getShort(2).toInt()
                    sampleRate = b.getInt(4)
                    bits = b.getShort(14).toInt()
                }
                "data" -> {
                    if (format != 1 || bits != 16 || channels !in 1..2 || sampleRate <= 0) {
                        throw IllegalArgumentException("unsupported WAV: format=$format bits=$bits channels=$channels")
                    }
                    // Some engines write 0 or 0xFFFFFFFF while streaming: use what is there.
                    val available = file.length() - file.filePointer
                    val dataSize = if (size == 0L || size > available) available else size
                    return Wav(sampleRate, channels, file.filePointer, dataSize)
                }
                else -> file.seek(file.filePointer + size + (size and 1))
            }
        }
        throw IllegalArgumentException("no audio data in WAV")
    }

    fun convert(input: String, output: String, bitrate: Int) {
        RandomAccessFile(input, "r").use { file ->
            val wav = readHeader(file)
            val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, wav.sampleRate, wav.channels)
            format.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            format.setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16 * 1024)

            val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            val muxer = MediaMuxer(output, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            var muxerStarted = false
            try {
                codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                codec.start()
                val bytesPerFrame = wav.channels * 2
                val buffer = ByteArray(16 * 1024)
                var remaining = wav.dataSize
                var presentationUs = 0L
                var inputDone = false
                var track = -1
                val info = MediaCodec.BufferInfo()
                file.seek(wav.dataOffset)

                while (true) {
                    if (!inputDone) {
                        val inIndex = codec.dequeueInputBuffer(TIMEOUT_US)
                        if (inIndex >= 0) {
                            val inBuf = codec.getInputBuffer(inIndex)!!
                            inBuf.clear()
                            // Whole frames only.
                            val want = minOf(inBuf.remaining(), buffer.size, remaining.toInt().coerceAtLeast(0))
                            val toRead = want - want % bytesPerFrame
                            val read = if (toRead > 0) file.read(buffer, 0, toRead) else -1
                            if (read <= 0) {
                                codec.queueInputBuffer(inIndex, 0, 0, presentationUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputDone = true
                            } else {
                                inBuf.put(buffer, 0, read)
                                codec.queueInputBuffer(inIndex, 0, read, presentationUs, 0)
                                presentationUs += read.toLong() / bytesPerFrame * 1_000_000L / wav.sampleRate
                                remaining -= read
                            }
                        }
                    }
                    val outIndex = codec.dequeueOutputBuffer(info, TIMEOUT_US)
                    if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        track = muxer.addTrack(codec.outputFormat)
                        muxer.start()
                        muxerStarted = true
                    } else if (outIndex >= 0) {
                        val outBuf = codec.getOutputBuffer(outIndex)!!
                        val isConfig = (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
                        if (!isConfig && info.size > 0 && muxerStarted) {
                            outBuf.position(info.offset)
                            outBuf.limit(info.offset + info.size)
                            muxer.writeSampleData(track, outBuf, info)
                        }
                        codec.releaseOutputBuffer(outIndex, false)
                        if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
                    }
                }
                if (!muxerStarted) throw IllegalStateException("encoder produced no output")
            } finally {
                try {
                    codec.stop()
                } catch (e: IllegalStateException) {
                    // already stopped after an error
                }
                codec.release()
                if (muxerStarted) muxer.stop()
                muxer.release()
            }
        }
    }
}
