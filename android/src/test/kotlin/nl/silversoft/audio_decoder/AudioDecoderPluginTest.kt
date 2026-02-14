package nl.silversoft.audio_decoder

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test

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
}
