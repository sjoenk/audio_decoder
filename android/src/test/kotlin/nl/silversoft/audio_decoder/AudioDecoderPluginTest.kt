package nl.silversoft.audio_decoder

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/*
 * Once you have built the plugin's example app, you can run these tests from the command
 * line by running `./gradlew testDebugUnitTest` in the `example/android/` directory, or
 * you can run them directly from IDEs that support JUnit such as Android Studio.
 */

internal class AudioDecoderPluginTest {
    @Test
    fun onMethodCall_unknownMethod_returnsNotImplemented() {
        val plugin = AudioDecoderPlugin()

        val call = MethodCall("nonExistentMethod", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).notImplemented()
    }

    @Test
    fun onMethodCall_convertToWav_missingArguments_returnsError() {
        val plugin = AudioDecoderPlugin()

        val call = MethodCall("convertToWav", mapOf("inputPath" to "/test.mp3"))
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            Mockito.eq("INVALID_ARGUMENTS"),
            Mockito.eq("inputPath and outputPath are required"),
            Mockito.isNull()
        )
    }

    @Test
    fun onMethodCall_convertToM4a_missingArguments_returnsError() {
        val plugin = AudioDecoderPlugin()

        val call = MethodCall("convertToM4a", mapOf("inputPath" to "/test.wav"))
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            Mockito.eq("INVALID_ARGUMENTS"),
            Mockito.eq("inputPath and outputPath are required"),
            Mockito.isNull()
        )
    }

    @Test
    fun onMethodCall_getAudioInfo_missingArguments_returnsError() {
        val plugin = AudioDecoderPlugin()

        val call = MethodCall("getAudioInfo", mapOf<String, Any>())
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            Mockito.eq("INVALID_ARGUMENTS"),
            Mockito.eq("path is required"),
            Mockito.isNull()
        )
    }

    @Test
    fun onMethodCall_trimAudio_missingArguments_returnsError() {
        val plugin = AudioDecoderPlugin()

        val call = MethodCall("trimAudio", mapOf("inputPath" to "/test.mp3", "outputPath" to "/out.wav"))
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            Mockito.eq("INVALID_ARGUMENTS"),
            Mockito.eq("inputPath, outputPath, startMs and endMs are required"),
            Mockito.isNull()
        )
    }

    @Test
    fun onMethodCall_getWaveform_missingArguments_returnsError() {
        val plugin = AudioDecoderPlugin()

        val call = MethodCall("getWaveform", mapOf<String, Any>())
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            Mockito.eq("INVALID_ARGUMENTS"),
            Mockito.eq("path and numberOfSamples are required"),
            Mockito.isNull()
        )
    }

    @Test
    fun onMethodCall_convertToWavBytes_missingArguments_returnsError() {
        val plugin = AudioDecoderPlugin()

        val call = MethodCall("convertToWavBytes", mapOf("formatHint" to "mp3"))
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            Mockito.eq("INVALID_ARGUMENTS"),
            Mockito.eq("inputData and formatHint are required"),
            Mockito.isNull()
        )
    }

    @Test
    fun onMethodCall_convertToM4aBytes_missingArguments_returnsError() {
        val plugin = AudioDecoderPlugin()

        val call = MethodCall("convertToM4aBytes", mapOf("formatHint" to "wav"))
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            Mockito.eq("INVALID_ARGUMENTS"),
            Mockito.eq("inputData and formatHint are required"),
            Mockito.isNull()
        )
    }

    @Test
    fun onMethodCall_getAudioInfoBytes_missingArguments_returnsError() {
        val plugin = AudioDecoderPlugin()

        val call = MethodCall("getAudioInfoBytes", mapOf<String, Any>())
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            Mockito.eq("INVALID_ARGUMENTS"),
            Mockito.eq("inputData and formatHint are required"),
            Mockito.isNull()
        )
    }

    @Test
    fun onMethodCall_trimAudioBytes_missingArguments_returnsError() {
        val plugin = AudioDecoderPlugin()

        val call = MethodCall("trimAudioBytes", mapOf("inputData" to ByteArray(1), "formatHint" to "mp3"))
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            Mockito.eq("INVALID_ARGUMENTS"),
            Mockito.eq("inputData, formatHint, startMs and endMs are required"),
            Mockito.isNull()
        )
    }

    @Test
    fun onMethodCall_getWaveformBytes_missingArguments_returnsError() {
        val plugin = AudioDecoderPlugin()

        val call = MethodCall("getWaveformBytes", mapOf("inputData" to ByteArray(1)))
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            Mockito.eq("INVALID_ARGUMENTS"),
            Mockito.eq("inputData, formatHint and numberOfSamples are required"),
            Mockito.isNull()
        )
    }

    @Test
    fun computeWaveform_largeSampleCount_doesNotOverflow() {
        val plugin = AudioDecoderPlugin()

        // Regression for #45: a multi-minute file decodes to millions of PCM
        // samples. With 32-bit window arithmetic `i * totalSamples` exceeds
        // Int.MAX_VALUE and wraps to a negative offset, crashing with an
        // IndexOutOfBoundsException. This sample count matches the length from
        // the original bug report.
        val numberOfSamples = 1000
        val samples = ShortArray(15_567_358) { 1000 }

        val waveform = plugin.computeWaveform(samples, numberOfSamples, "perFile")

        assertEquals(numberOfSamples, waveform.size)
        assertTrue(waveform.all { it in 0.0..1.0 })
    }

    @Test
    fun computeWaveform_emptySamples_returnsZeroFilledWaveform() {
        val plugin = AudioDecoderPlugin()

        val waveform = plugin.computeWaveform(ShortArray(0), 256, "perFile")

        assertEquals(256, waveform.size)
        assertTrue(waveform.all { it == 0.0 })
    }

    @Test
    fun computeWaveform_absoluteNormalization_scalesByFullScale() {
        val plugin = AudioDecoderPlugin()

        // A constant full-scale signal must normalize to 1.0 in absolute mode.
        val samples = ShortArray(2048) { Short.MAX_VALUE }

        val waveform = plugin.computeWaveform(samples, 128, "absolute")

        assertEquals(128, waveform.size)
        assertTrue(waveform.all { it > 0.99 && it <= 1.0 })
    }

    @Test
    fun waveformAccumulator_chunkedPcm_matchesSingleArray() {
        // Regression for #49: the waveform is accumulated while decoding, so
        // feeding the same signal in chunks must give the same result as
        // handing over one array — including when a sample straddles a chunk
        // boundary (odd chunk size).
        val samples = ShortArray(5_000) { (it * 37 % 20_000 - 10_000).toShort() }
        val pcm = ByteArray(samples.size * 2)
        for (i in samples.indices) {
            pcm[i * 2] = (samples[i].toInt() and 0xFF).toByte()
            pcm[i * 2 + 1] = ((samples[i].toInt() shr 8) and 0xFF).toByte()
        }

        val chunked = AudioDecoderPlugin.WaveformAccumulator(100)
        var offset = 0
        val chunkSize = 777
        while (offset < pcm.size) {
            val size = minOf(chunkSize, pcm.size - offset)
            chunked.addPcm(pcm.copyOfRange(offset, offset + size))
            offset += size
        }

        val expected = AudioDecoderPlugin().computeWaveform(samples, 100, "perFile")
        val actual = chunked.build("perFile")

        assertEquals(expected.size, actual.size)
        for (i in expected.indices) {
            assertTrue(
                kotlin.math.abs(expected[i] - actual[i]) < 1e-9,
                "point $i: expected ${expected[i]}, got ${actual[i]}"
            )
        }
    }

    @Test
    fun waveformAccumulator_moreSamplesThanBuckets_staysNormalized() {
        // Well past the bucket capacity, so the accumulator merges buckets
        // repeatedly. A constant signal must still come out flat and in range.
        val accumulator = AudioDecoderPlugin.WaveformAccumulator(100)
        val chunk = ShortArray(100_000) { 8_000 }
        repeat(50) { accumulator.addSamples(chunk, chunk.size) }

        val waveform = accumulator.build("absolute")

        assertEquals(100, waveform.size)
        assertTrue(waveform.all { kotlin.math.abs(it - 8_000.0 / 32_768.0) < 1e-6 })
    }
}
