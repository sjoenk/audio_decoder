package nl.silversoft.audio_decoder

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import android.media.MediaCodecInfo
import android.media.MediaMuxer
import android.content.Context
import java.io.Closeable
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread
import kotlin.math.sqrt
import kotlin.math.max
import kotlin.math.floor
import kotlin.math.min

class AudioDecoderPlugin : FlutterPlugin, MethodCallHandler {
    companion object {
        /// Standard RIFF/WAV header size in bytes (no extra chunks).
        private const val WAV_HEADER_SIZE = 44

        /// Maximum PCM data size for a standard WAV file.
        /// The RIFF chunk header stores total file size minus 8 as a uint32,
        /// so the data payload can be at most 2^32 - 1 - 36 bytes (~4 GB).
        private const val MAX_WAV_DATA_SIZE = 0xFFFFFFFFL - 36L

        /// Maximum supported target sample rate (384 kHz covers all standard
        /// audio formats including DXD and high-resolution PCM).
        private const val MAX_SAMPLE_RATE = 384_000

        /// Timeout for MediaCodec buffer dequeue calls.
        private const val CODEC_TIMEOUT_US = 10_000L
    }

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "audio_decoder")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "convertToWav" -> {
                val inputPath = call.argument<String>("inputPath")
                val outputPath = call.argument<String>("outputPath")
                if (inputPath == null || outputPath == null) {
                    result.error("INVALID_ARGUMENTS", "inputPath and outputPath are required", null)
                    return
                }
                val targetSampleRate = call.argument<Int>("sampleRate")
                val targetChannels = call.argument<Int>("channels")
                val targetBitDepth = call.argument<Int>("bitDepth")
                thread {
                    try {
                        performConversion(inputPath, outputPath, targetSampleRate, targetChannels, targetBitDepth)
                        Handler(Looper.getMainLooper()).post {
                            result.success(outputPath)
                        }
                    } catch (e: Exception) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("CONVERSION_ERROR", e.message, null)
                        }
                    }
                }
            }
            "convertToM4a" -> {
                val inputPath = call.argument<String>("inputPath")
                val outputPath = call.argument<String>("outputPath")
                if (inputPath == null || outputPath == null) {
                    result.error("INVALID_ARGUMENTS", "inputPath and outputPath are required", null)
                    return
                }
                thread {
                    try {
                        performM4aConversion(inputPath, outputPath)
                        Handler(Looper.getMainLooper()).post {
                            result.success(outputPath)
                        }
                    } catch (e: Exception) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("CONVERSION_ERROR", e.message, null)
                        }
                    }
                }
            }
            "getAudioInfo" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("INVALID_ARGUMENTS", "path is required", null)
                    return
                }
                thread {
                    try {
                        val info = performGetAudioInfo(path)
                        Handler(Looper.getMainLooper()).post {
                            result.success(info)
                        }
                    } catch (e: Exception) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("INFO_ERROR", e.message, null)
                        }
                    }
                }
            }
            "trimAudio" -> {
                val inputPath = call.argument<String>("inputPath")
                val outputPath = call.argument<String>("outputPath")
                val startMs = call.argument<Int>("startMs")
                val endMs = call.argument<Int>("endMs")
                if (inputPath == null || outputPath == null || startMs == null || endMs == null) {
                    result.error("INVALID_ARGUMENTS", "inputPath, outputPath, startMs and endMs are required", null)
                    return
                }
                thread {
                    try {
                        performTrimAudio(inputPath, outputPath, startMs.toLong(), endMs.toLong())
                        Handler(Looper.getMainLooper()).post {
                            result.success(outputPath)
                        }
                    } catch (e: Exception) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("TRIM_ERROR", e.message, null)
                        }
                    }
                }
            }
            "getWaveform" -> {
                val path = call.argument<String>("path")
                val numberOfSamples = call.argument<Int>("numberOfSamples")
                val normalization = call.argument<String>("normalization") ?: "perFile"
                if (path == null || numberOfSamples == null) {
                    result.error("INVALID_ARGUMENTS", "path and numberOfSamples are required", null)
                    return
                }
                thread {
                    try {
                        val waveform = performGetWaveform(path, numberOfSamples, normalization)
                        Handler(Looper.getMainLooper()).post {
                            result.success(waveform)
                        }
                    } catch (e: Exception) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("WAVEFORM_ERROR", e.message, null)
                        }
                    }
                }
            }
            "convertToWavBytes" -> {
                val inputData = call.argument<ByteArray>("inputData")
                val formatHint = call.argument<String>("formatHint")
                if (inputData == null || formatHint == null) {
                    result.error("INVALID_ARGUMENTS", "inputData and formatHint are required", null)
                    return
                }
                val targetSampleRate = call.argument<Int>("sampleRate")
                val targetChannels = call.argument<Int>("channels")
                val targetBitDepth = call.argument<Int>("bitDepth")
                val includeHeader = call.argument<Boolean>("includeHeader") ?: true
                thread {
                    try {
                        val tempInput = writeTempInput(inputData, formatHint)
                        val tempOutput = File(context.cacheDir, "audio_decoder_out_${System.nanoTime()}.wav")
                        try {
                            performConversion(tempInput.absolutePath, tempOutput.absolutePath, targetSampleRate, targetChannels, targetBitDepth)
                            var outputBytes = tempOutput.readBytes()
                            // Strip the WAV header to return raw PCM.
                            if (!includeHeader && outputBytes.size >= WAV_HEADER_SIZE) {
                                outputBytes = outputBytes.copyOfRange(WAV_HEADER_SIZE, outputBytes.size)
                            }
                            Handler(Looper.getMainLooper()).post { result.success(outputBytes) }
                        } finally {
                            tempInput.delete()
                            tempOutput.delete()
                        }
                    } catch (e: Exception) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("CONVERSION_ERROR", e.message, null)
                        }
                    }
                }
            }
            "convertToM4aBytes" -> {
                val inputData = call.argument<ByteArray>("inputData")
                val formatHint = call.argument<String>("formatHint")
                if (inputData == null || formatHint == null) {
                    result.error("INVALID_ARGUMENTS", "inputData and formatHint are required", null)
                    return
                }
                thread {
                    try {
                        val tempInput = writeTempInput(inputData, formatHint)
                        val tempOutput = File(context.cacheDir, "audio_decoder_out_${System.nanoTime()}.m4a")
                        try {
                            performM4aConversion(tempInput.absolutePath, tempOutput.absolutePath)
                            val outputBytes = tempOutput.readBytes()
                            Handler(Looper.getMainLooper()).post { result.success(outputBytes) }
                        } finally {
                            tempInput.delete()
                            tempOutput.delete()
                        }
                    } catch (e: Exception) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("CONVERSION_ERROR", e.message, null)
                        }
                    }
                }
            }
            "getAudioInfoBytes" -> {
                val inputData = call.argument<ByteArray>("inputData")
                val formatHint = call.argument<String>("formatHint")
                if (inputData == null || formatHint == null) {
                    result.error("INVALID_ARGUMENTS", "inputData and formatHint are required", null)
                    return
                }
                thread {
                    try {
                        val tempInput = writeTempInput(inputData, formatHint)
                        try {
                            val info = performGetAudioInfo(tempInput.absolutePath)
                            Handler(Looper.getMainLooper()).post { result.success(info) }
                        } finally {
                            tempInput.delete()
                        }
                    } catch (e: Exception) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("INFO_ERROR", e.message, null)
                        }
                    }
                }
            }
            "trimAudioBytes" -> {
                val inputData = call.argument<ByteArray>("inputData")
                val formatHint = call.argument<String>("formatHint")
                val startMs = call.argument<Int>("startMs")
                val endMs = call.argument<Int>("endMs")
                val outputFormat = call.argument<String>("outputFormat") ?: "wav"
                if (inputData == null || formatHint == null || startMs == null || endMs == null) {
                    result.error("INVALID_ARGUMENTS", "inputData, formatHint, startMs and endMs are required", null)
                    return
                }
                thread {
                    try {
                        val tempInput = writeTempInput(inputData, formatHint)
                        val tempOutput = File(context.cacheDir, "audio_decoder_out_${System.nanoTime()}.$outputFormat")
                        try {
                            performTrimAudio(tempInput.absolutePath, tempOutput.absolutePath, startMs.toLong(), endMs.toLong())
                            val outputBytes = tempOutput.readBytes()
                            Handler(Looper.getMainLooper()).post { result.success(outputBytes) }
                        } finally {
                            tempInput.delete()
                            tempOutput.delete()
                        }
                    } catch (e: Exception) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("TRIM_ERROR", e.message, null)
                        }
                    }
                }
            }
            "getWaveformBytes" -> {
                val inputData = call.argument<ByteArray>("inputData")
                val formatHint = call.argument<String>("formatHint")
                val numberOfSamples = call.argument<Int>("numberOfSamples")
                val normalization = call.argument<String>("normalization") ?: "perFile"
                if (inputData == null || formatHint == null || numberOfSamples == null) {
                    result.error("INVALID_ARGUMENTS", "inputData, formatHint and numberOfSamples are required", null)
                    return
                }
                thread {
                    try {
                        val tempInput = writeTempInput(inputData, formatHint)
                        try {
                            val waveform = performGetWaveform(tempInput.absolutePath, numberOfSamples, normalization)
                            Handler(Looper.getMainLooper()).post { result.success(waveform) }
                        } finally {
                            tempInput.delete()
                        }
                    } catch (e: Exception) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("WAVEFORM_ERROR", e.message, null)
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    // region Temp file helpers

    private fun writeTempInput(data: ByteArray, formatHint: String): File {
        val tempFile = File(context.cacheDir, "audio_decoder_in_${System.nanoTime()}.$formatHint")
        tempFile.writeBytes(data)
        return tempFile
    }

    // endregion

    // region Convert to WAV

    private data class AudioTrackInfo(
        val extractor: MediaExtractor,
        val format: MediaFormat,
        val mime: String,
        val sampleRate: Int,
        val channelCount: Int
    )

    private fun extractAudioTrack(inputPath: String): AudioTrackInfo {
        val extractor = MediaExtractor()
        extractor.setDataSource(inputPath)

        for (i in 0 until extractor.trackCount) {
            val trackFormat = extractor.getTrackFormat(i)
            val mime = trackFormat.getString(MediaFormat.KEY_MIME) ?: ""
            if (mime.startsWith("audio/")) {
                extractor.selectTrack(i)
                return AudioTrackInfo(
                    extractor = extractor,
                    format = trackFormat,
                    mime = mime,
                    sampleRate = trackFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE),
                    channelCount = trackFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                )
            }
        }

        extractor.release()
        throw Exception("No audio track found in $inputPath")
    }

    private fun performConversion(inputPath: String, outputPath: String, targetSampleRate: Int? = null, targetChannels: Int? = null, targetBitDepth: Int? = null) {
        val track = extractAudioTrack(inputPath)
        try {
            val bitsPerSample = targetBitDepth ?: 16

            val needsResampling = targetSampleRate != null && targetSampleRate != track.sampleRate
            if (targetSampleRate != null && targetSampleRate > MAX_SAMPLE_RATE) {
                throw IllegalArgumentException("targetSampleRate $targetSampleRate exceeds maximum ($MAX_SAMPLE_RATE)")
            }
            val codec = MediaCodec.createDecoderByType(track.mime)
            try {
                codec.configure(track.format, null, null, 0)
                codec.start()

                val channelCount = targetChannels ?: track.channelCount
                val sampleRate = if (needsResampling) targetSampleRate!! else track.sampleRate
                val needsChannelConversion = targetChannels != null && targetChannels != track.channelCount
                val needsBitDepthConversion = bitsPerSample != 16
                val resamplerState = if (needsResampling) ResamplerState(
                    step = track.sampleRate.toDouble() / targetSampleRate!!.toDouble(),
                    channels = channelCount
                ) else null

                val bufferInfo = MediaCodec.BufferInfo()
                var inputDone = false
                var outputDone = false
                val timeoutUs = 10_000L
                val outputFile = File(outputPath)
                outputFile.delete()

                RandomAccessFile(outputFile, "rw").use { raf ->
                    // Write placeholder WAV header (will be updated after decoding)
                    raf.write(buildWavHeader(0, sampleRate, channelCount, bitsPerSample))

                    var totalPcmBytes = 0L

                    while (!outputDone) {
                        if (!inputDone) {
                            val inputBufferIndex = codec.dequeueInputBuffer(timeoutUs)
                            if (inputBufferIndex >= 0) {
                                val inputBuffer = codec.getInputBuffer(inputBufferIndex)!!
                                val sampleSize = track.extractor.readSampleData(inputBuffer, 0)
                                if (sampleSize < 0) {
                                    codec.queueInputBuffer(
                                        inputBufferIndex, 0, 0, 0,
                                        MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                    )
                                    inputDone = true
                                } else {
                                    val presentationTimeUs = track.extractor.sampleTime
                                    codec.queueInputBuffer(
                                        inputBufferIndex, 0, sampleSize,
                                        presentationTimeUs, 0
                                    )
                                    track.extractor.advance()
                                }
                            }
                        }

                        val outputBufferIndex = codec.dequeueOutputBuffer(bufferInfo, timeoutUs)
                        if (outputBufferIndex >= 0) {
                            val isLastChunk = bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                            if (isLastChunk) {
                                outputDone = true
                            }
                            if (bufferInfo.size > 0) {
                                val outputBuffer = codec.getOutputBuffer(outputBufferIndex)!!
                                outputBuffer.position(bufferInfo.offset)
                                outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                                val rawChunk = ByteArray(bufferInfo.size)
                                outputBuffer.get(rawChunk)

                                val chunk = rawChunk
                                    .let { if (needsChannelConversion) convertChannels(it, track.channelCount, targetChannels!!) else it }
                                    .let { if (resamplerState != null) resampleChunk(resamplerState, it, isLastChunk) else it }
                                    .let { if (needsBitDepthConversion) convertBitDepth(it, 16, bitsPerSample) else it }

                                raf.write(chunk)
                                totalPcmBytes += chunk.size
                                if (totalPcmBytes > MAX_WAV_DATA_SIZE) {
                                    throw Exception("WAV output exceeds maximum size (~4 GB). Consider splitting the audio into shorter segments.")
                                }
                            } else if (isLastChunk && resamplerState != null) {
                                // Flush remaining fractional samples from the resampler
                                val flush = resampleChunk(resamplerState, ByteArray(0), true)
                                if (flush.isNotEmpty()) {
                                    val chunk = if (needsBitDepthConversion) convertBitDepth(flush, 16, bitsPerSample) else flush
                                    raf.write(chunk)
                                    totalPcmBytes += chunk.size
                                    if (totalPcmBytes > MAX_WAV_DATA_SIZE) {
                                        throw Exception("WAV output exceeds maximum size (~4 GB). Consider splitting the audio into shorter segments.")
                                    }
                                }
                            }
                            codec.releaseOutputBuffer(outputBufferIndex, false)
                        }
                    }

                    // Seek back and write the final WAV header with the actual data size.
                    // The toInt() cast is safe: totalPcmBytes is validated against
                    // MAX_WAV_DATA_SIZE, so the bit pattern is a valid uint32 value
                    // that ByteBuffer.putInt writes correctly in little-endian.
                    raf.seek(0)
                    raf.write(buildWavHeader(totalPcmBytes.toInt(), sampleRate, channelCount, bitsPerSample))
                }
            } catch (e: Exception) {
                File(outputPath).delete()
                throw e
            } finally {
                try { codec.stop() } catch (_: IllegalStateException) {}
                codec.release()
            }
        } finally {
            track.extractor.release()
        }
    }

    private class ResamplerState(
        val step: Double,
        val channels: Int
    ) {
        var srcPos: Double = 0.0
        var lastFrame: ShortArray? = null
    }

    private fun resampleChunk(state: ResamplerState, chunk: ByteArray, isLastChunk: Boolean): ByteArray {
        val bytesPerFrame = state.channels * 2
        val chunkFrames = chunk.size / bytesPerFrame
        if (chunkFrames == 0 && state.lastFrame == null) return ByteArray(0)

        val srcBuf = if (chunkFrames > 0) ByteBuffer.wrap(chunk).order(ByteOrder.LITTLE_ENDIAN) else null
        val maxFrames = ((chunkFrames + 1).toDouble() / state.step).toInt() + 2
        val output = ByteArray(maxFrames * bytesPerFrame)
        val outBuf = ByteBuffer.wrap(output).order(ByteOrder.LITTLE_ENDIAN)
        var outFrames = 0

        while (true) {
            val idx0 = floor(state.srcPos).toInt()
            val idx1 = idx0 + 1

            if (idx0 >= chunkFrames) break
            if (idx1 >= chunkFrames && !isLastChunk) break

            val frac = state.srcPos - idx0
            for (ch in 0 until state.channels) {
                val s0 = if (idx0 < 0) {
                    state.lastFrame?.get(ch)?.toInt() ?: 0
                } else {
                    srcBuf!!.getShort(idx0 * bytesPerFrame + ch * 2).toInt()
                }
                val s1 = if (idx1 >= chunkFrames) {
                    s0
                } else {
                    srcBuf!!.getShort(idx1 * bytesPerFrame + ch * 2).toInt()
                }
                val interpolated = (s0 + (s1 - s0) * frac).toInt().coerceIn(-32768, 32767).toShort()
                outBuf.putShort(interpolated)
            }
            outFrames++

            state.srcPos += state.step
        }

        if (chunkFrames > 0) {
            // Save last frame for interpolation across chunk boundaries
            val lf = ShortArray(state.channels)
            for (ch in 0 until state.channels) {
                lf[ch] = srcBuf!!.getShort((chunkFrames - 1) * bytesPerFrame + ch * 2)
            }
            state.lastFrame = lf

            // Adjust position relative to next chunk
            state.srcPos -= chunkFrames
        }

        val totalBytes = outFrames * bytesPerFrame
        return if (totalBytes == output.size) output else output.copyOf(totalBytes)
    }

    private fun convertChannels(pcmData: ByteArray, srcChannels: Int, dstChannels: Int): ByteArray {
        val srcBytesPerFrame = srcChannels * 2 // 16-bit
        val dstBytesPerFrame = dstChannels * 2
        val numFrames = pcmData.size / srcBytesPerFrame
        val output = ByteArray(numFrames * dstBytesPerFrame)
        val srcBuf = ByteBuffer.wrap(pcmData).order(ByteOrder.LITTLE_ENDIAN)
        val dstBuf = ByteBuffer.wrap(output).order(ByteOrder.LITTLE_ENDIAN)

        for (i in 0 until numFrames) {
            val samples = ShortArray(srcChannels)
            for (ch in 0 until srcChannels) {
                samples[ch] = srcBuf.getShort(i * srcBytesPerFrame + ch * 2)
            }
            if (dstChannels < srcChannels) {
                // Mix down to fewer channels
                var sum = 0L
                for (s in samples) sum += s.toLong()
                val mixed = (sum / srcChannels).toInt().coerceIn(-32768, 32767).toShort()
                for (ch in 0 until dstChannels) {
                    dstBuf.putShort(i * dstBytesPerFrame + ch * 2, mixed)
                }
            } else {
                // Upmix: duplicate existing channels
                for (ch in 0 until dstChannels) {
                    dstBuf.putShort(i * dstBytesPerFrame + ch * 2, samples[if (ch < srcChannels) ch else 0])
                }
            }
        }
        return output
    }

    private fun convertBitDepth(pcmData: ByteArray, srcBits: Int, dstBits: Int): ByteArray {
        val srcBytesPerSample = srcBits / 8
        val dstBytesPerSample = dstBits / 8
        val numSamples = pcmData.size / srcBytesPerSample
        val output = ByteArray(numSamples * dstBytesPerSample)
        val srcBuf = ByteBuffer.wrap(pcmData).order(ByteOrder.LITTLE_ENDIAN)
        val dstBuf = ByteBuffer.wrap(output).order(ByteOrder.LITTLE_ENDIAN)

        for (i in 0 until numSamples) {
            val sample16 = srcBuf.getShort(i * srcBytesPerSample).toInt()
            when (dstBits) {
                8 -> output[i] = ((sample16 / 256) + 128).coerceIn(0, 255).toByte()
                16 -> dstBuf.putShort(i * 2, sample16.toShort())
                24 -> {
                    val s24 = sample16 shl 8
                    output[i * 3] = (s24 and 0xFF).toByte()
                    output[i * 3 + 1] = ((s24 shr 8) and 0xFF).toByte()
                    output[i * 3 + 2] = ((s24 shr 16) and 0xFF).toByte()
                }
                32 -> dstBuf.putInt(i * 4, sample16 shl 16)
            }
        }
        return output
    }

    // endregion

    // region PCM streaming

    /**
     * Pull-based source of decoded 16-bit PCM.
     *
     * Consumers request one chunk at a time so a track never has to be held in
     * memory as a whole: three hours of 44.1 kHz stereo audio decodes to roughly
     * 1.9 GB of PCM, far beyond the per-app heap limit on Android.
     */
    private interface PcmSource {
        /** The next PCM chunk, or `null` once the stream is exhausted. */
        fun next(): ByteArray?
    }

    /**
     * Decodes an audio track on demand with [MediaCodec].
     *
     * Each [next] call runs the codec loop just far enough to produce one output
     * chunk, so the decoder stays one buffer ahead of its consumer instead of
     * collecting every chunk up front. When [timeRangeUs] is set, only samples
     * whose presentation time falls inside the range are emitted and input
     * feeding stops as soon as the extractor passes the end of the range.
     */
    private class PcmDecoder(
        private val track: AudioTrackInfo,
        private val timeRangeUs: LongRange? = null,
    ) : PcmSource, Closeable {
        val sampleRate: Int get() = track.sampleRate
        val channelCount: Int get() = track.channelCount

        private val decoder = MediaCodec.createDecoderByType(track.mime)
        private val bufferInfo = MediaCodec.BufferInfo()
        private var inputDone = false
        private var outputDone = false
        private var released = false

        init {
            if (timeRangeUs != null && timeRangeUs.first > 0) {
                track.extractor.seekTo(timeRangeUs.first, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
            }
            decoder.configure(track.format, null, null, 0)
            decoder.start()
        }

        override fun next(): ByteArray? {
            while (!outputDone) {
                if (!inputDone) {
                    val idx = decoder.dequeueInputBuffer(CODEC_TIMEOUT_US)
                    if (idx >= 0) {
                        val buf = decoder.getInputBuffer(idx)!!
                        val size = track.extractor.readSampleData(buf, 0)
                        val sampleTime = track.extractor.sampleTime
                        val pastRange = timeRangeUs != null && sampleTime > timeRangeUs.last
                        if (size < 0 || pastRange) {
                            decoder.queueInputBuffer(idx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(idx, 0, size, sampleTime, 0)
                            track.extractor.advance()
                        }
                    }
                }

                val idx = decoder.dequeueOutputBuffer(bufferInfo, CODEC_TIMEOUT_US)
                if (idx >= 0) {
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        outputDone = true
                    }
                    val inRange = timeRangeUs == null || bufferInfo.presentationTimeUs in timeRangeUs
                    var chunk: ByteArray? = null
                    if (bufferInfo.size > 0 && inRange) {
                        val buf = decoder.getOutputBuffer(idx)!!
                        buf.position(bufferInfo.offset)
                        buf.limit(bufferInfo.offset + bufferInfo.size)
                        chunk = ByteArray(bufferInfo.size)
                        buf.get(chunk)
                    }
                    decoder.releaseOutputBuffer(idx, false)
                    if (chunk != null) return chunk
                }
            }
            return null
        }

        override fun close() {
            if (released) return
            released = true
            try { decoder.stop() } catch (_: IllegalStateException) {}
            decoder.release()
            track.extractor.release()
        }
    }

    /**
     * Opens a [PcmDecoder] for [inputPath] and releases both the codec and the
     * extractor when [block] returns or throws.
     */
    private inline fun <T> withPcmSource(
        inputPath: String,
        timeRangeUs: LongRange? = null,
        block: (PcmDecoder) -> T,
    ): T {
        val track = extractAudioTrack(inputPath)
        val decoder = try {
            PcmDecoder(track, timeRangeUs)
        } catch (e: Exception) {
            track.extractor.release()
            throw e
        }
        return decoder.use(block)
    }

    /**
     * Streams every chunk of [source] into a RIFF/WAV file at [outputPath],
     * patching the header with the final data size once the stream ends.
     */
    private fun streamPcmToWav(
        source: PcmSource,
        outputPath: String,
        sampleRate: Int,
        channelCount: Int,
        bitsPerSample: Int,
    ) {
        val outputFile = File(outputPath)
        outputFile.delete()
        try {
            RandomAccessFile(outputFile, "rw").use { raf ->
                // Placeholder header; rewritten below with the actual data size.
                raf.write(buildWavHeader(0, sampleRate, channelCount, bitsPerSample))

                var totalPcmBytes = 0L
                while (true) {
                    val chunk = source.next() ?: break
                    raf.write(chunk)
                    totalPcmBytes += chunk.size
                    if (totalPcmBytes > MAX_WAV_DATA_SIZE) {
                        throw Exception("WAV output exceeds maximum size (~4 GB). Consider splitting the audio into shorter segments.")
                    }
                }

                // The toInt() cast is safe: totalPcmBytes is validated against
                // MAX_WAV_DATA_SIZE, so the bit pattern is a valid uint32 value
                // that ByteBuffer.putInt writes correctly in little-endian.
                raf.seek(0)
                raf.write(buildWavHeader(totalPcmBytes.toInt(), sampleRate, channelCount, bitsPerSample))
            }
        } catch (e: Exception) {
            outputFile.delete()
            throw e
        }
    }

    // endregion

    // region Convert to M4A

    private fun performM4aConversion(inputPath: String, outputPath: String) {
        // Decoding and encoding are interleaved: each PCM chunk is handed to the
        // AAC encoder as soon as it comes out of the decoder, so peak memory
        // stays independent of the audio duration.
        withPcmSource(inputPath) { source ->
            encodePcmToM4a(source, outputPath, source.sampleRate, source.channelCount)
        }
    }

    // endregion

    // region Get Audio Info

    private fun performGetAudioInfo(path: String): Map<String, Any> {
        val extractor = MediaExtractor()
        extractor.setDataSource(path)

        var audioTrackIndex = -1
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val trackFormat = extractor.getTrackFormat(i)
            val mime = trackFormat.getString(MediaFormat.KEY_MIME) ?: ""
            if (mime.startsWith("audio/")) {
                audioTrackIndex = i
                format = trackFormat
                break
            }
        }
        if (audioTrackIndex == -1 || format == null) {
            extractor.release()
            throw Exception("No audio track found in $path")
        }

        val sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channelCount = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) {
            format.getLong(MediaFormat.KEY_DURATION)
        } else {
            0L
        }
        val durationMs = (durationUs / 1000).toInt()
        val bitRate = if (format.containsKey(MediaFormat.KEY_BIT_RATE)) {
            format.getInteger(MediaFormat.KEY_BIT_RATE)
        } else {
            0
        }
        val mime = format.getString(MediaFormat.KEY_MIME) ?: "unknown"
        val formatStr = mimeToFormat(mime)

        extractor.release()

        return mapOf(
            "durationMs" to durationMs,
            "sampleRate" to sampleRate,
            "channels" to channelCount,
            "bitRate" to bitRate,
            "format" to formatStr,
        )
    }

    private fun mimeToFormat(mime: String): String {
        return when (mime) {
            "audio/mpeg" -> "mp3"
            "audio/mp4a-latm" -> "aac"
            "audio/flac" -> "flac"
            "audio/vorbis" -> "vorbis"
            "audio/opus" -> "opus"
            "audio/raw" -> "pcm"
            "audio/amr-wb" -> "amr"
            "audio/3gpp" -> "amr"
            else -> mime.removePrefix("audio/")
        }
    }

    // endregion

    // region Trim Audio

    private fun performTrimAudio(inputPath: String, outputPath: String, startMs: Long, endMs: Long) {
        val bitsPerSample = 16
        val timeRangeUs = (startMs * 1000) until (endMs * 1000)
        val outputExt = outputPath.substringAfterLast('.').lowercase()

        // The trimmed range is streamed straight to the encoder or to disk; a
        // trim that spans hours of audio therefore costs no more memory than a
        // trim of a few seconds.
        withPcmSource(inputPath, timeRangeUs) { source ->
            if (outputExt == "m4a") {
                encodePcmToM4a(source, outputPath, source.sampleRate, source.channelCount)
            } else {
                streamPcmToWav(source, outputPath, source.sampleRate, source.channelCount, bitsPerSample)
            }
        }
    }

    // endregion

    // region Get Waveform

    private fun performGetWaveform(
        path: String,
        numberOfSamples: Int,
        normalization: String = "perFile",
    ): List<Double> {
        // Fail fast on an invalid normalization mode before setting up the
        // MediaExtractor and decoding the PCM samples.
        if (normalization != "perFile" && normalization != "absolute") {
            throw IllegalArgumentException(
                "Unknown waveform normalization: $normalization"
            )
        }

        val accumulator = WaveformAccumulator(numberOfSamples)
        withPcmSource(path) { source ->
            while (true) {
                val chunk = source.next() ?: break
                accumulator.addPcm(chunk)
            }
        }
        return accumulator.build(normalization)
    }

    /**
     * Reduces decoded 16-bit PCM [samples] to a normalized RMS waveform of
     * [numberOfSamples] points. Thin wrapper around [WaveformAccumulator] for
     * callers that already hold the full sample array.
     */
    internal fun computeWaveform(
        samples: ShortArray,
        numberOfSamples: Int,
        normalization: String = "perFile",
    ): List<Double> {
        val accumulator = WaveformAccumulator(numberOfSamples)
        accumulator.addSamples(samples, samples.size)
        return accumulator.build(normalization)
    }

    /**
     * Accumulates RMS energy for a waveform while the audio is still decoding.
     *
     * Holding every decoded sample is not an option — three hours of 44.1 kHz
     * stereo audio is close to a billion samples — so energy is folded into a
     * fixed set of buckets instead. Each bucket covers [samplesPerBucket]
     * consecutive samples; once the array is full, adjacent buckets are merged
     * pairwise and the span per bucket doubles. Memory therefore stays bounded
     * regardless of duration, while short inputs (which never trigger a merge)
     * are summarized sample-exact.
     *
     * The window bounds in [build] are computed with 64-bit arithmetic on
     * purpose: for longer files the product `i * totalSamples` easily exceeds
     * Int.MAX_VALUE, which would silently overflow to a negative offset (#45).
     * The caller is expected to validate the normalization mode beforehand.
     */
    internal class WaveformAccumulator(private val numberOfSamples: Int) {
        private val sumSquares: DoubleArray
        private val counts: LongArray

        /** Number of samples each full bucket covers; doubles on every merge. */
        private var samplesPerBucket = 1L
        private var bucketCount = 0
        private var totalSamples = 0L
        private var pendingByte: Byte = 0
        private var hasPendingByte = false

        init {
            // Aim for BUCKETS_PER_WINDOW buckets per output point so window
            // bounds land close to a bucket edge, keeping the RMS error
            // negligible once merging kicks in.
            val target = numberOfSamples.toLong() * BUCKETS_PER_WINDOW
            val capacity = target.coerceIn(MIN_BUCKETS, MAX_BUCKETS).toInt()
            // An even capacity keeps pairwise merging exact.
            val evenCapacity = capacity + (capacity % 2)
            sumSquares = DoubleArray(evenCapacity)
            counts = LongArray(evenCapacity)
        }

        /**
         * Adds a chunk of interleaved little-endian 16-bit PCM. A sample split
         * across two chunks is carried over instead of dropped.
         */
        fun addPcm(chunk: ByteArray) {
            var offset = 0
            if (hasPendingByte && chunk.isNotEmpty()) {
                add(littleEndianShort(pendingByte, chunk[0]))
                hasPendingByte = false
                offset = 1
            }
            while (offset + 1 < chunk.size) {
                add(littleEndianShort(chunk[offset], chunk[offset + 1]))
                offset += 2
            }
            if (offset < chunk.size) {
                pendingByte = chunk[offset]
                hasPendingByte = true
            }
        }

        private fun littleEndianShort(low: Byte, high: Byte): Short =
            (((high.toInt() and 0xFF) shl 8) or (low.toInt() and 0xFF)).toShort()

        /** Adds the first [count] samples of [samples]. */
        fun addSamples(samples: ShortArray, count: Int) {
            for (i in 0 until count) {
                add(samples[i])
            }
        }

        private fun add(sample: Short) {
            if (bucketCount == 0 || counts[bucketCount - 1] >= samplesPerBucket) {
                if (bucketCount == counts.size) mergeAdjacentBuckets()
                bucketCount++
                sumSquares[bucketCount - 1] = 0.0
                counts[bucketCount - 1] = 0L
            }
            val value = sample.toDouble()
            sumSquares[bucketCount - 1] += value * value
            counts[bucketCount - 1]++
            totalSamples++
        }

        /** Halves the resolution so more samples fit in the same arrays. */
        private fun mergeAdjacentBuckets() {
            var dst = 0
            var src = 0
            while (src < bucketCount) {
                sumSquares[dst] = sumSquares[src] + sumSquares[src + 1]
                counts[dst] = counts[src] + counts[src + 1]
                dst++
                src += 2
            }
            bucketCount = dst
            samplesPerBucket *= 2
        }

        /** Sum of squares over the sample range `[start, end)`. */
        private fun sumSquaresIn(start: Long, end: Long): Double {
            var sum = 0.0
            // Every bucket but the last is full, so bucket b starts at
            // b * samplesPerBucket.
            var bucket = (start / samplesPerBucket).toInt()
            while (bucket < bucketCount) {
                val bucketStart = bucket.toLong() * samplesPerBucket
                if (bucketStart >= end) break
                val bucketEnd = bucketStart + counts[bucket]
                val overlap = min(end, bucketEnd) - max(start, bucketStart)
                if (overlap > 0) {
                    sum += if (overlap >= counts[bucket]) {
                        sumSquares[bucket]
                    } else {
                        // Partial overlap: assume the energy is spread evenly
                        // across the bucket.
                        sumSquares[bucket] * overlap / counts[bucket]
                    }
                }
                bucket++
            }
            return sum
        }

        /** Builds the normalized waveform from everything accumulated so far. */
        fun build(normalization: String): List<Double> {
            if (totalSamples == 0L) {
                return List(numberOfSamples) { 0.0 }
            }

            val windowSize = max(1L, totalSamples / numberOfSamples)
            val waveform = mutableListOf<Double>()
            var maxRms = 0.0

            for (i in 0 until numberOfSamples) {
                val start = i.toLong() * totalSamples / numberOfSamples
                if (start >= totalSamples) break
                val end = min(start + windowSize, totalSamples)

                val rms = sqrt(sumSquaresIn(start, end) / (end - start))
                waveform.add(rms)
                if (rms > maxRms) maxRms = rms
            }

            // Scale to 0.0-1.0 according to the requested normalization mode.
            // Samples are signed 16-bit PCM with range [-32768, 32767], so the
            // absolute mode divides by the max magnitude (32768) to keep the
            // result inside [0.0, 1.0] even when a window is filled with -32768.
            // (normalization is already validated up front.)
            val normalized = if (normalization == "absolute") {
                waveform.map { it / 32768.0 }
            } else if (maxRms > 0) {
                waveform.map { it / maxRms }
            } else {
                waveform
            }

            // Pad if needed
            return if (normalized.size < numberOfSamples) {
                normalized + List(numberOfSamples - normalized.size) { 0.0 }
            } else {
                normalized
            }
        }

        private companion object {
            const val BUCKETS_PER_WINDOW = 256L
            const val MIN_BUCKETS = 1024L

            /// Caps the accumulator at ~4 MB (one Double plus one Long per bucket).
            const val MAX_BUCKETS = 262_144L
        }
    }

    // endregion

    // region M4A encoding helper

    /**
     * Encodes the PCM delivered by [source] to AAC and muxes it into an M4A
     * file at [outputPath].
     *
     * Chunks are pulled from [source] one at a time while the encoder drains, so
     * only the chunk currently being copied into an input buffer is held in
     * memory (#49).
     */
    private fun encodePcmToM4a(source: PcmSource, outputPath: String, sampleRate: Int, channelCount: Int) {
        val outputFile = File(outputPath)
        if (outputFile.exists()) outputFile.delete()

        val encoderFormat = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channelCount)
        encoderFormat.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
        encoderFormat.setInteger(MediaFormat.KEY_BIT_RATE, 128_000)
        encoderFormat.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)

        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        val muxer: MediaMuxer
        try {
            encoder.configure(encoderFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()
            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        } catch (e: Exception) {
            encoder.release()
            outputFile.delete()
            throw e
        }

        var muxerTrackIndex = -1
        var muxerStarted = false

        val encBufferInfo = MediaCodec.BufferInfo()
        var currentChunk: ByteArray? = source.next()
        var chunkOffset = 0
        var encInputDone = false
        var encOutputDone = false
        var framesEncoded = 0L
        val bytesPerFrame = 2 * channelCount

        try {
            while (!encOutputDone) {
                if (!encInputDone) {
                    val idx = encoder.dequeueInputBuffer(CODEC_TIMEOUT_US)
                    if (idx >= 0) {
                        val buf = encoder.getInputBuffer(idx)!!
                        buf.clear()
                        // Fill whole frames only, so the frame count below stays
                        // exact even when the buffer size is not a multiple of
                        // the frame size (e.g. multi-channel audio). Buffers too
                        // small for a single frame fall back to a plain fill.
                        val alignedCapacity = (buf.remaining() / bytesPerFrame) * bytesPerFrame
                        val limit = if (alignedCapacity > 0) alignedCapacity else buf.remaining()
                        var written = 0
                        while (written < limit) {
                            val chunk = currentChunk ?: break
                            val toCopy = minOf(chunk.size - chunkOffset, limit - written)
                            buf.put(chunk, chunkOffset, toCopy)
                            written += toCopy
                            chunkOffset += toCopy
                            if (chunkOffset >= chunk.size) {
                                currentChunk = source.next()
                                chunkOffset = 0
                            }
                        }
                        // Derive the timestamp from the running frame count
                        // instead of accumulating per-buffer deltas, which would
                        // drift on long recordings.
                        val presentationTimeUs = framesEncoded * 1_000_000L / sampleRate
                        if (written == 0) {
                            encoder.queueInputBuffer(idx, 0, 0, presentationTimeUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            encInputDone = true
                        } else {
                            encoder.queueInputBuffer(idx, 0, written, presentationTimeUs, 0)
                            framesEncoded += written / bytesPerFrame
                        }
                    }
                }
                val idx = encoder.dequeueOutputBuffer(encBufferInfo, CODEC_TIMEOUT_US)
                if (idx >= 0) {
                    if (encBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        encOutputDone = true
                    }
                    // Codec-specific data reaches the muxer through the output
                    // format, so it must not be written as a sample.
                    val isCodecConfig = encBufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    if (encBufferInfo.size > 0 && muxerStarted && !isCodecConfig) {
                        val buf = encoder.getOutputBuffer(idx)!!
                        buf.position(encBufferInfo.offset)
                        buf.limit(encBufferInfo.offset + encBufferInfo.size)
                        muxer.writeSampleData(muxerTrackIndex, buf, encBufferInfo)
                    }
                    encoder.releaseOutputBuffer(idx, false)
                } else if (idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    muxerTrackIndex = muxer.addTrack(encoder.outputFormat)
                    muxer.start()
                    muxerStarted = true
                }
            }

            if (muxerStarted) {
                muxer.stop()
            }
        } catch (e: Exception) {
            outputFile.delete()
            throw e
        } finally {
            try { encoder.stop() } catch (_: IllegalStateException) {}
            encoder.release()
            muxer.release()
        }
    }

    // endregion

    // region WAV header helper

    private fun buildWavHeader(
        pcmDataSize: Int, sampleRate: Int, channels: Int, bitsPerSample: Int
    ): ByteArray {
        val byteRate = sampleRate * channels * bitsPerSample / 8
        val blockAlign = channels * bitsPerSample / 8
        val buffer = ByteBuffer.allocate(WAV_HEADER_SIZE).order(ByteOrder.LITTLE_ENDIAN)

        buffer.put("RIFF".toByteArray(Charsets.US_ASCII))
        buffer.putInt(36 + pcmDataSize)
        buffer.put("WAVE".toByteArray(Charsets.US_ASCII))
        buffer.put("fmt ".toByteArray(Charsets.US_ASCII))
        buffer.putInt(16)
        buffer.putShort(1)
        buffer.putShort(channels.toShort())
        buffer.putInt(sampleRate)
        buffer.putInt(byteRate)
        buffer.putShort(blockAlign.toShort())
        buffer.putShort(bitsPerSample.toShort())
        buffer.put("data".toByteArray(Charsets.US_ASCII))
        buffer.putInt(pcmDataSize)

        return buffer.array()
    }

    // endregion

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
