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
import java.io.ByteArrayOutputStream
import android.content.Context
import java.io.File
import java.io.FileOutputStream
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
                if (path == null || numberOfSamples == null) {
                    result.error("INVALID_ARGUMENTS", "path and numberOfSamples are required", null)
                    return
                }
                thread {
                    try {
                        val waveform = performGetWaveform(path, numberOfSamples)
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
                if (inputData == null || formatHint == null || numberOfSamples == null) {
                    result.error("INVALID_ARGUMENTS", "inputData, formatHint and numberOfSamples are required", null)
                    return
                }
                thread {
                    try {
                        val tempInput = writeTempInput(inputData, formatHint)
                        try {
                            val waveform = performGetWaveform(tempInput.absolutePath, numberOfSamples)
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

    // region Convert to M4A

    private fun performM4aConversion(inputPath: String, outputPath: String) {
        // Step 1: Decode input to PCM
        val extractor = MediaExtractor()
        extractor.setDataSource(inputPath)

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
            throw Exception("No audio track found in $inputPath")
        }

        extractor.selectTrack(audioTrackIndex)

        val mime = format.getString(MediaFormat.KEY_MIME)!!
        val sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channelCount = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

        val decoder = MediaCodec.createDecoderByType(mime)
        decoder.configure(format, null, null, 0)
        decoder.start()

        val pcmChunks = mutableListOf<ByteArray>()
        val bufferInfo = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false
        val timeoutUs = 10_000L

        while (!outputDone) {
            if (!inputDone) {
                val idx = decoder.dequeueInputBuffer(timeoutUs)
                if (idx >= 0) {
                    val buf = decoder.getInputBuffer(idx)!!
                    val size = extractor.readSampleData(buf, 0)
                    if (size < 0) {
                        decoder.queueInputBuffer(idx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        decoder.queueInputBuffer(idx, 0, size, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }
            val idx = decoder.dequeueOutputBuffer(bufferInfo, timeoutUs)
            if (idx >= 0) {
                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                    outputDone = true
                }
                if (bufferInfo.size > 0) {
                    val buf = decoder.getOutputBuffer(idx)!!
                    val chunk = ByteArray(bufferInfo.size)
                    buf.get(chunk)
                    pcmChunks.add(chunk)
                }
                decoder.releaseOutputBuffer(idx, false)
            }
        }
        decoder.stop()
        decoder.release()
        extractor.release()

        // Step 2: Encode PCM to AAC and mux into M4A
        encodePcmToM4a(pcmChunks, outputPath, sampleRate, channelCount)
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
        val extractor = MediaExtractor()
        extractor.setDataSource(inputPath)

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
            throw Exception("No audio track found in $inputPath")
        }

        extractor.selectTrack(audioTrackIndex)

        val mime = format.getString(MediaFormat.KEY_MIME)!!
        val sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channelCount = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val bitsPerSample = 16

        val startUs = startMs * 1000
        val endUs = endMs * 1000

        // Seek to start position
        extractor.seekTo(startUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)

        val decoder = MediaCodec.createDecoderByType(mime)
        decoder.configure(format, null, null, 0)
        decoder.start()

        val pcmChunks = mutableListOf<ByteArray>()
        val bufferInfo = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false
        val timeoutUs = 10_000L

        while (!outputDone) {
            if (!inputDone) {
                val idx = decoder.dequeueInputBuffer(timeoutUs)
                if (idx >= 0) {
                    val buf = decoder.getInputBuffer(idx)!!
                    val sampleSize = extractor.readSampleData(buf, 0)
                    val sampleTime = extractor.sampleTime
                    if (sampleSize < 0 || sampleTime > endUs) {
                        decoder.queueInputBuffer(idx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        decoder.queueInputBuffer(idx, 0, sampleSize, sampleTime, 0)
                        extractor.advance()
                    }
                }
            }
            val idx = decoder.dequeueOutputBuffer(bufferInfo, timeoutUs)
            if (idx >= 0) {
                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                    outputDone = true
                }
                if (bufferInfo.size > 0) {
                    // Filter samples by time range
                    val ts = bufferInfo.presentationTimeUs
                    if (ts >= startUs && ts < endUs) {
                        val buf = decoder.getOutputBuffer(idx)!!
                        val chunk = ByteArray(bufferInfo.size)
                        buf.get(chunk)
                        pcmChunks.add(chunk)
                    }
                }
                decoder.releaseOutputBuffer(idx, false)
            }
        }
        decoder.stop()
        decoder.release()
        extractor.release()

        val outputExt = outputPath.substringAfterLast('.').lowercase()
        if (outputExt == "m4a") {
            encodePcmToM4a(pcmChunks, outputPath, sampleRate, channelCount)
        } else {
            // Write WAV
            val pcmOutput = ByteArrayOutputStream()
            for (chunk in pcmChunks) {
                pcmOutput.write(chunk)
            }
            val pcmData = pcmOutput.toByteArray()
            FileOutputStream(File(outputPath)).use { fos ->
                fos.write(buildWavHeader(pcmData.size, sampleRate, channelCount, bitsPerSample))
                fos.write(pcmData)
            }
        }
    }

    // endregion

    // region Get Waveform

    private fun performGetWaveform(path: String, numberOfSamples: Int): List<Double> {
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

        extractor.selectTrack(audioTrackIndex)

        val mime = format.getString(MediaFormat.KEY_MIME)!!
        val codec = MediaCodec.createDecoderByType(mime)
        codec.configure(format, null, null, 0)
        codec.start()

        val allSamples = mutableListOf<Short>()
        val bufferInfo = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false
        val timeoutUs = 10_000L

        while (!outputDone) {
            if (!inputDone) {
                val idx = codec.dequeueInputBuffer(timeoutUs)
                if (idx >= 0) {
                    val buf = codec.getInputBuffer(idx)!!
                    val size = extractor.readSampleData(buf, 0)
                    if (size < 0) {
                        codec.queueInputBuffer(idx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        codec.queueInputBuffer(idx, 0, size, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }
            val idx = codec.dequeueOutputBuffer(bufferInfo, timeoutUs)
            if (idx >= 0) {
                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                    outputDone = true
                }
                if (bufferInfo.size > 0) {
                    val buf = codec.getOutputBuffer(idx)!!
                    val shortBuf = buf.order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
                    val samples = ShortArray(bufferInfo.size / 2)
                    shortBuf.get(samples)
                    for (s in samples) {
                        allSamples.add(s)
                    }
                }
                codec.releaseOutputBuffer(idx, false)
            }
        }
        codec.stop()
        codec.release()
        extractor.release()

        if (allSamples.isEmpty()) {
            return List(numberOfSamples) { 0.0 }
        }

        // Compute RMS per window
        val waveform = mutableListOf<Double>()
        var maxRms = 0.0

        for (i in 0 until numberOfSamples) {
            val start = i * allSamples.size / numberOfSamples
            val end = min(start + max(1, allSamples.size / numberOfSamples), allSamples.size)
            if (start >= allSamples.size) break

            var sumSquares = 0.0
            for (j in start until end) {
                val sample = allSamples[j].toDouble()
                sumSquares += sample * sample
            }
            val rms = sqrt(sumSquares / (end - start))
            waveform.add(rms)
            if (rms > maxRms) maxRms = rms
        }

        // Normalize to 0.0-1.0
        val normalized = if (maxRms > 0) {
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

    // endregion

    // region M4A encoding helper

    private fun encodePcmToM4a(pcmChunks: List<ByteArray>, outputPath: String, sampleRate: Int, channelCount: Int) {
        val outputFile = File(outputPath)
        if (outputFile.exists()) outputFile.delete()

        val encoderFormat = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channelCount)
        encoderFormat.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
        encoderFormat.setInteger(MediaFormat.KEY_BIT_RATE, 128_000)
        encoderFormat.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)

        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        encoder.configure(encoderFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        encoder.start()

        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var muxerTrackIndex = -1
        var muxerStarted = false

        val encBufferInfo = MediaCodec.BufferInfo()
        var pcmOffset = 0
        var chunkIndex = 0
        var encInputDone = false
        var encOutputDone = false
        var presentationTimeUs = 0L
        val bytesPerSample = 2 * channelCount
        val timeoutUs = 10_000L

        while (!encOutputDone) {
            if (!encInputDone) {
                val idx = encoder.dequeueInputBuffer(timeoutUs)
                if (idx >= 0) {
                    val buf = encoder.getInputBuffer(idx)!!
                    buf.clear()
                    var written = 0
                    while (chunkIndex < pcmChunks.size && written < buf.remaining()) {
                        val chunk = pcmChunks[chunkIndex]
                        val available = chunk.size - pcmOffset
                        val toCopy = minOf(available, buf.remaining())
                        buf.put(chunk, pcmOffset, toCopy)
                        written += toCopy
                        pcmOffset += toCopy
                        if (pcmOffset >= chunk.size) {
                            pcmOffset = 0
                            chunkIndex++
                        }
                    }
                    if (written == 0) {
                        encoder.queueInputBuffer(idx, 0, 0, presentationTimeUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        encInputDone = true
                    } else {
                        encoder.queueInputBuffer(idx, 0, written, presentationTimeUs, 0)
                        presentationTimeUs += (written.toLong() / bytesPerSample) * 1_000_000L / sampleRate
                    }
                }
            }
            val idx = encoder.dequeueOutputBuffer(encBufferInfo, timeoutUs)
            if (idx >= 0) {
                if (encBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                    encOutputDone = true
                }
                if (encBufferInfo.size > 0 && muxerStarted) {
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

        encoder.stop()
        encoder.release()
        if (muxerStarted) {
            muxer.stop()
        }
        muxer.release()
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
