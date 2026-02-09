#include "include/audio_decoder/audio_decoder_plugin.h"

#include <flutter_linux/flutter_linux.h>

#include <gst/gst.h>
#include <gst/audio/audio.h>
#include <gst/pbutils/pbutils.h>
#include <gst/app/gstappsink.h>

#include <cmath>
#include <cstdio>
#include <cstring>
#include <algorithm>
#include <fstream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
#include <thread>

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

struct PcmResult {
    std::vector<uint8_t> data;
    uint32_t sampleRate;
    uint32_t channels;
    uint32_t bitsPerSample;
};

static PcmResult DecodeToPcm(const std::string& inputPath,
                              int64_t startMs = -1, int64_t endMs = -1,
                              int targetSampleRate = -1, int targetChannels = -1,
                              int targetBitDepth = -1) {
    PcmResult result{};

    std::string uri;
    if (inputPath.rfind("file://", 0) == 0) {
        uri = inputPath;
    } else {
        gchar* fileUri = g_filename_to_uri(inputPath.c_str(), nullptr, nullptr);
        if (!fileUri) {
            throw std::runtime_error("Cannot convert path to URI: " + inputPath);
        }
        uri = fileUri;
        g_free(fileUri);
    }

    // Determine output format based on bit depth
    std::string gstFormat = "S16LE";
    if (targetBitDepth == 8) gstFormat = "S8";
    else if (targetBitDepth == 24) gstFormat = "S24LE";
    else if (targetBitDepth == 32) gstFormat = "S32LE";

    // Build caps string with optional rate/channels
    std::string capsStr = "audio/x-raw,format=" + gstFormat;
    if (targetSampleRate > 0) {
        capsStr += ",rate=" + std::to_string(targetSampleRate);
    }
    if (targetChannels > 0) {
        capsStr += ",channels=" + std::to_string(targetChannels);
    }

    // Build pipeline: uridecodebin ! audioconvert ! audioresample ! appsink
    std::string pipeDesc =
        "uridecodebin uri=\"" + uri + "\" ! audioconvert ! audioresample ! "
        + capsStr + " ! appsink name=sink sync=false";

    GError* error = nullptr;
    GstElement* pipeline = gst_parse_launch(pipeDesc.c_str(), &error);
    if (!pipeline || error) {
        std::string msg = error ? error->message : "Unknown error";
        if (error) g_error_free(error);
        if (pipeline) gst_object_unref(pipeline);
        throw std::runtime_error("Failed to create pipeline: " + msg);
    }

    GstElement* sink = gst_bin_get_by_name(GST_BIN(pipeline), "sink");
    if (!sink) {
        gst_object_unref(pipeline);
        throw std::runtime_error("Failed to get appsink element");
    }
    g_object_set(sink, "emit-signals", FALSE, "max-buffers", 0, nullptr);

    gst_element_set_state(pipeline, GST_STATE_PLAYING);

    // Seek to start position if specified
    if (startMs >= 0) {
        gst_element_seek_simple(pipeline, GST_FORMAT_TIME,
            static_cast<GstSeekFlags>(GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_KEY_UNIT),
            startMs * GST_MSECOND);
    }

    // Pull samples from appsink
    bool gotCaps = false;
    while (true) {
        GstSample* sample = gst_app_sink_pull_sample(GST_APP_SINK(sink));
        if (!sample) break;

        if (!gotCaps) {
            GstCaps* caps = gst_sample_get_caps(sample);
            if (caps) {
                GstAudioInfo info;
                if (gst_audio_info_from_caps(&info, caps)) {
                    result.sampleRate = info.rate;
                    result.channels = info.channels;
                    result.bitsPerSample = info.finfo->width;
                    gotCaps = true;
                }
            }
        }

        GstBuffer* buffer = gst_sample_get_buffer(sample);
        if (buffer) {
            // Check end position
            if (endMs >= 0) {
                gint64 pts = GST_BUFFER_PTS(buffer);
                if (GST_CLOCK_TIME_IS_VALID(pts) &&
                    pts >= static_cast<guint64>(endMs) * GST_MSECOND) {
                    gst_sample_unref(sample);
                    break;
                }
            }

            GstMapInfo map;
            if (gst_buffer_map(buffer, &map, GST_MAP_READ)) {
                result.data.insert(result.data.end(), map.data, map.data + map.size);
                gst_buffer_unmap(buffer, &map);
            }
        }
        gst_sample_unref(sample);
    }

    gst_element_set_state(pipeline, GST_STATE_NULL);
    gst_object_unref(sink);
    gst_object_unref(pipeline);

    return result;
}

static void WriteWavHeader(std::ofstream& file, uint32_t dataSize,
                           uint32_t sampleRate, uint16_t channels,
                           uint16_t bitsPerSample) {
    uint32_t byteRate = sampleRate * channels * bitsPerSample / 8;
    uint16_t blockAlign = channels * bitsPerSample / 8;
    uint32_t chunkSize = 36 + dataSize;
    uint32_t subChunk1Size = 16;
    uint16_t audioFormat = 1;

    file.write("RIFF", 4);
    file.write(reinterpret_cast<char*>(&chunkSize), 4);
    file.write("WAVE", 4);
    file.write("fmt ", 4);
    file.write(reinterpret_cast<char*>(&subChunk1Size), 4);
    file.write(reinterpret_cast<char*>(&audioFormat), 2);
    file.write(reinterpret_cast<char*>(&channels), 2);
    file.write(reinterpret_cast<char*>(&sampleRate), 4);
    file.write(reinterpret_cast<char*>(&byteRate), 4);
    file.write(reinterpret_cast<char*>(&blockAlign), 2);
    file.write(reinterpret_cast<char*>(&bitsPerSample), 2);
    file.write("data", 4);
    file.write(reinterpret_cast<char*>(&dataSize), 4);
}

static std::string WriteTempFile(const std::vector<uint8_t>& data,
                                 const std::string& extension) {
    std::string templ = "/tmp/audio_decoder_XXXXXX." + extension;
    std::vector<char> buf(templ.begin(), templ.end());
    buf.push_back('\0');

    int fd = mkstemps(buf.data(), static_cast<int>(extension.size() + 1));
    if (fd < 0) {
        throw std::runtime_error("Failed to create temp file");
    }

    if (!data.empty()) {
        ssize_t written = write(fd, data.data(), data.size());
        (void)written;
    }
    close(fd);
    return std::string(buf.data());
}

static std::vector<uint8_t> ReadAndDeleteFile(const std::string& path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file.is_open()) {
        throw std::runtime_error("Cannot read output file");
    }
    auto size = file.tellg();
    file.seekg(0, std::ios::beg);
    std::vector<uint8_t> bytes(size);
    file.read(reinterpret_cast<char*>(bytes.data()), size);
    file.close();
    std::remove(path.c_str());
    return bytes;
}

// ---------------------------------------------------------------------------
// Core operations
// ---------------------------------------------------------------------------

static std::string ConvertToWav(const std::string& inputPath,
                                const std::string& outputPath,
                                int targetSampleRate = -1,
                                int targetChannels = -1,
                                int targetBitDepth = -1) {
    auto pcm = DecodeToPcm(inputPath, -1, -1, targetSampleRate, targetChannels, targetBitDepth);
    if (pcm.data.empty()) {
        throw std::runtime_error("No audio data decoded from input file");
    }

    std::ofstream file(outputPath, std::ios::binary);
    if (!file.is_open()) {
        throw std::runtime_error("Cannot open output file for writing");
    }

    WriteWavHeader(file, static_cast<uint32_t>(pcm.data.size()), pcm.sampleRate,
                   static_cast<uint16_t>(pcm.channels),
                   static_cast<uint16_t>(pcm.bitsPerSample));
    file.write(reinterpret_cast<char*>(pcm.data.data()), pcm.data.size());
    file.close();
    return outputPath;
}

static std::string ConvertToM4a(const std::string& inputPath,
                                const std::string& outputPath) {
    auto pcm = DecodeToPcm(inputPath);
    if (pcm.data.empty()) {
        throw std::runtime_error("No audio data decoded from input file");
    }

    // Write PCM to temp WAV, then encode to M4A via GStreamer pipeline
    std::string tempWav = WriteTempFile({}, "wav");
    {
        std::ofstream wf(tempWav, std::ios::binary);
        WriteWavHeader(wf, static_cast<uint32_t>(pcm.data.size()), pcm.sampleRate,
                       static_cast<uint16_t>(pcm.channels),
                       static_cast<uint16_t>(pcm.bitsPerSample));
        wf.write(reinterpret_cast<char*>(pcm.data.data()), pcm.data.size());
        wf.close();
    }

    gchar* srcUri = g_filename_to_uri(tempWav.c_str(), nullptr, nullptr);
    std::string pipeDesc =
        std::string("uridecodebin uri=\"") + srcUri + "\" ! audioconvert ! "
        "avenc_aac ! mp4mux ! filesink location=\"" + outputPath + "\"";
    g_free(srcUri);

    GError* error = nullptr;
    GstElement* pipeline = gst_parse_launch(pipeDesc.c_str(), &error);
    if (!pipeline || error) {
        std::string msg = error ? error->message : "Unknown error";
        if (error) g_error_free(error);
        if (pipeline) gst_object_unref(pipeline);
        std::remove(tempWav.c_str());
        throw std::runtime_error("Failed to create M4A encoding pipeline: " + msg);
    }

    gst_element_set_state(pipeline, GST_STATE_PLAYING);

    GstBus* bus = gst_element_get_bus(pipeline);
    GstMessage* msg = gst_bus_timed_pop_filtered(bus, GST_CLOCK_TIME_NONE,
        static_cast<GstMessageType>(GST_MESSAGE_ERROR | GST_MESSAGE_EOS));

    bool success = true;
    std::string errMsg;
    if (msg) {
        if (GST_MESSAGE_TYPE(msg) == GST_MESSAGE_ERROR) {
            GError* err = nullptr;
            gst_message_parse_error(msg, &err, nullptr);
            errMsg = err ? err->message : "Unknown encoding error";
            if (err) g_error_free(err);
            success = false;
        }
        gst_message_unref(msg);
    }

    gst_object_unref(bus);
    gst_element_set_state(pipeline, GST_STATE_NULL);
    gst_object_unref(pipeline);
    std::remove(tempWav.c_str());

    if (!success) {
        throw std::runtime_error("M4A encoding failed: " + errMsg);
    }

    return outputPath;
}

static FlValue* GetAudioInfo(const std::string& path) {
    gchar* uri = nullptr;
    if (path.rfind("file://", 0) == 0) {
        uri = g_strdup(path.c_str());
    } else {
        uri = g_filename_to_uri(path.c_str(), nullptr, nullptr);
    }
    if (!uri) {
        throw std::runtime_error("Cannot convert path to URI");
    }

    GError* error = nullptr;
    GstDiscoverer* discoverer = gst_discoverer_new(5 * GST_SECOND, &error);
    if (!discoverer) {
        std::string msg = error ? error->message : "Unknown error";
        if (error) g_error_free(error);
        g_free(uri);
        throw std::runtime_error("Failed to create discoverer: " + msg);
    }

    GstDiscovererInfo* info = gst_discoverer_discover_uri(discoverer, uri, &error);
    g_free(uri);

    if (!info || error) {
        std::string msg = error ? error->message : "Unknown error";
        if (error) g_error_free(error);
        if (info) gst_discoverer_info_unref(info);
        g_object_unref(discoverer);
        throw std::runtime_error("Failed to discover audio info: " + msg);
    }

    GstClockTime duration = gst_discoverer_info_get_duration(info);
    int64_t durationMs = static_cast<int64_t>(duration / GST_MSECOND);

    // Get audio stream info
    GList* audioStreams = gst_discoverer_info_get_audio_streams(info);
    int32_t sampleRate = 0, channels = 0, bitRate = 0;
    std::string format = "unknown";

    if (audioStreams) {
        GstDiscovererAudioInfo* audioInfo =
            static_cast<GstDiscovererAudioInfo*>(audioStreams->data);
        sampleRate = static_cast<int32_t>(
            gst_discoverer_audio_info_get_sample_rate(audioInfo));
        channels = static_cast<int32_t>(
            gst_discoverer_audio_info_get_channels(audioInfo));
        bitRate = static_cast<int32_t>(
            gst_discoverer_audio_info_get_bitrate(audioInfo));

        // Detect format from caps
        GstCaps* caps = gst_discoverer_stream_info_get_caps(
            GST_DISCOVERER_STREAM_INFO(audioInfo));
        if (caps) {
            GstStructure* s = gst_caps_get_structure(caps, 0);
            const gchar* name = gst_structure_get_name(s);
            if (g_str_has_prefix(name, "audio/mpeg")) {
                gint mpegversion = 0;
                gst_structure_get_int(s, "mpegversion", &mpegversion);
                gint layer = 0;
                gst_structure_get_int(s, "layer", &layer);
                if (mpegversion == 1 && layer == 3) format = "mp3";
                else if (mpegversion == 4 || mpegversion == 2) format = "aac";
                else format = "mpeg";
            } else if (g_str_has_prefix(name, "audio/x-flac")) {
                format = "flac";
            } else if (g_str_has_prefix(name, "audio/x-vorbis")) {
                format = "ogg";
            } else if (g_str_has_prefix(name, "audio/x-opus")) {
                format = "opus";
            } else if (g_str_has_prefix(name, "audio/x-wav") ||
                       g_str_has_prefix(name, "audio/x-raw")) {
                format = "wav";
            } else if (g_str_has_prefix(name, "audio/x-aiff")) {
                format = "aiff";
            } else if (g_str_has_prefix(name, "audio/x-alac")) {
                format = "alac";
            } else if (g_str_has_prefix(name, "audio/AMR")) {
                format = "amr";
            } else if (g_str_has_prefix(name, "audio/x-wma")) {
                format = "wma";
            }
            gst_caps_unref(caps);
        }
        gst_discoverer_stream_info_list_free(audioStreams);
    }

    gst_discoverer_info_unref(info);
    g_object_unref(discoverer);

    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "durationMs",
        fl_value_new_int(static_cast<int64_t>(durationMs)));
    fl_value_set_string_take(map, "sampleRate",
        fl_value_new_int(sampleRate));
    fl_value_set_string_take(map, "channels",
        fl_value_new_int(channels));
    fl_value_set_string_take(map, "bitRate",
        fl_value_new_int(bitRate));
    fl_value_set_string_take(map, "format",
        fl_value_new_string(format.c_str()));
    return map;
}

static std::string TrimAudio(const std::string& inputPath,
                             const std::string& outputPath,
                             int64_t startMs, int64_t endMs) {
    auto pcm = DecodeToPcm(inputPath, startMs, endMs);
    if (pcm.data.empty()) {
        throw std::runtime_error("No audio data decoded from trim range");
    }

    std::string ext = outputPath.substr(outputPath.find_last_of('.') + 1);
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);

    if (ext == "m4a") {
        // Encode trimmed PCM to M4A
        std::string tempWav = WriteTempFile({}, "wav");
        {
            std::ofstream wf(tempWav, std::ios::binary);
            WriteWavHeader(wf, static_cast<uint32_t>(pcm.data.size()),
                           pcm.sampleRate,
                           static_cast<uint16_t>(pcm.channels),
                           static_cast<uint16_t>(pcm.bitsPerSample));
            wf.write(reinterpret_cast<char*>(pcm.data.data()), pcm.data.size());
            wf.close();
        }

        gchar* srcUri = g_filename_to_uri(tempWav.c_str(), nullptr, nullptr);
        std::string pipeDesc =
            std::string("uridecodebin uri=\"") + srcUri + "\" ! audioconvert ! "
            "avenc_aac ! mp4mux ! filesink location=\"" + outputPath + "\"";
        g_free(srcUri);

        GError* error = nullptr;
        GstElement* pipeline = gst_parse_launch(pipeDesc.c_str(), &error);
        if (!pipeline || error) {
            std::string msg = error ? error->message : "Unknown error";
            if (error) g_error_free(error);
            if (pipeline) gst_object_unref(pipeline);
            std::remove(tempWav.c_str());
            throw std::runtime_error("Failed to create M4A pipeline: " + msg);
        }

        gst_element_set_state(pipeline, GST_STATE_PLAYING);
        GstBus* bus = gst_element_get_bus(pipeline);
        GstMessage* msg = gst_bus_timed_pop_filtered(bus, GST_CLOCK_TIME_NONE,
            static_cast<GstMessageType>(GST_MESSAGE_ERROR | GST_MESSAGE_EOS));

        bool success = true;
        std::string errMsg;
        if (msg) {
            if (GST_MESSAGE_TYPE(msg) == GST_MESSAGE_ERROR) {
                GError* err = nullptr;
                gst_message_parse_error(msg, &err, nullptr);
                errMsg = err ? err->message : "Unknown error";
                if (err) g_error_free(err);
                success = false;
            }
            gst_message_unref(msg);
        }

        gst_object_unref(bus);
        gst_element_set_state(pipeline, GST_STATE_NULL);
        gst_object_unref(pipeline);
        std::remove(tempWav.c_str());

        if (!success) {
            throw std::runtime_error("M4A encoding failed: " + errMsg);
        }
    } else {
        std::ofstream file(outputPath, std::ios::binary);
        if (!file.is_open()) {
            throw std::runtime_error("Cannot open output file for writing");
        }
        WriteWavHeader(file, static_cast<uint32_t>(pcm.data.size()),
                       pcm.sampleRate,
                       static_cast<uint16_t>(pcm.channels),
                       static_cast<uint16_t>(pcm.bitsPerSample));
        file.write(reinterpret_cast<char*>(pcm.data.data()), pcm.data.size());
        file.close();
    }

    return outputPath;
}

static FlValue* GetWaveform(const std::string& path, int numberOfSamples) {
    auto pcm = DecodeToPcm(path);

    FlValue* list = fl_value_new_list();

    if (pcm.data.empty()) {
        for (int i = 0; i < numberOfSamples; i++) {
            fl_value_append_take(list, fl_value_new_float(0.0));
        }
        return list;
    }

    const int16_t* samples = reinterpret_cast<const int16_t*>(pcm.data.data());
    size_t totalSamples = pcm.data.size() / 2;
    size_t samplesPerWindow =
        std::max(static_cast<size_t>(1), totalSamples / numberOfSamples);

    std::vector<double> waveform;
    double maxRms = 0;

    for (int i = 0; i < numberOfSamples; i++) {
        size_t start = static_cast<size_t>(i) * totalSamples / numberOfSamples;
        size_t end = std::min(start + samplesPerWindow, totalSamples);
        if (start >= totalSamples) break;

        double sumSquares = 0;
        for (size_t j = start; j < end; j++) {
            double s = static_cast<double>(samples[j]);
            sumSquares += s * s;
        }
        double rms = std::sqrt(sumSquares / (end - start));
        waveform.push_back(rms);
        if (rms > maxRms) maxRms = rms;
    }

    for (size_t i = 0; i < waveform.size(); i++) {
        double normalized = (maxRms > 0) ? waveform[i] / maxRms : 0.0;
        fl_value_append_take(list, fl_value_new_float(normalized));
    }

    while (fl_value_get_length(list) < static_cast<size_t>(numberOfSamples)) {
        fl_value_append_take(list, fl_value_new_float(0.0));
    }

    return list;
}

// ---------------------------------------------------------------------------
// Flutter plugin glue
// ---------------------------------------------------------------------------

#define AUDIO_DECODER_PLUGIN(obj) \
    (G_TYPE_CHECK_INSTANCE_CAST((obj), audio_decoder_plugin_get_type(), \
                                AudioDecoderPlugin))

struct _AudioDecoderPlugin {
    GObject parent_instance;
    FlMethodChannel* channel;
};

G_DEFINE_TYPE(AudioDecoderPlugin, audio_decoder_plugin, g_object_get_type())

static void send_success(FlMethodCall* method_call, FlValue* result) {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    fl_method_call_respond(method_call, response, nullptr);
}

static void send_error(FlMethodCall* method_call, const char* code,
                       const char* message) {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_error_response_new(code, message, nullptr));
    fl_method_call_respond(method_call, response, nullptr);
}

static void handle_method_call(AudioDecoderPlugin* self,
                               FlMethodCall* method_call) {
    const gchar* method = fl_method_call_get_name(method_call);
    FlValue* args = fl_method_call_get_args(method_call);

    // ---- convertToWav ----
    if (strcmp(method, "convertToWav") == 0) {
        if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
            send_error(method_call, "INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        FlValue* inputVal = fl_value_lookup_string(args, "inputPath");
        FlValue* outputVal = fl_value_lookup_string(args, "outputPath");
        if (!inputVal || !outputVal) {
            send_error(method_call, "INVALID_ARGUMENTS",
                       "inputPath and outputPath are required");
            return;
        }
        std::string inputPath = fl_value_get_string(inputVal);
        std::string outputPath = fl_value_get_string(outputVal);

        int targetSampleRate = -1, targetChannels = -1, targetBitDepth = -1;
        FlValue* srVal = fl_value_lookup_string(args, "sampleRate");
        if (srVal && fl_value_get_type(srVal) == FL_VALUE_TYPE_INT)
            targetSampleRate = static_cast<int>(fl_value_get_int(srVal));
        FlValue* chVal = fl_value_lookup_string(args, "channels");
        if (chVal && fl_value_get_type(chVal) == FL_VALUE_TYPE_INT)
            targetChannels = static_cast<int>(fl_value_get_int(chVal));
        FlValue* bdVal = fl_value_lookup_string(args, "bitDepth");
        if (bdVal && fl_value_get_type(bdVal) == FL_VALUE_TYPE_INT)
            targetBitDepth = static_cast<int>(fl_value_get_int(bdVal));

        g_object_ref(method_call);
        std::thread([method_call, inputPath, outputPath, targetSampleRate, targetChannels, targetBitDepth]() {
            try {
                std::string result = ConvertToWav(inputPath, outputPath, targetSampleRate, targetChannels, targetBitDepth);
                g_autoptr(FlValue) val = fl_value_new_string(result.c_str());
                send_success(method_call, val);
            } catch (const std::exception& e) {
                send_error(method_call, "CONVERSION_ERROR", e.what());
            }
            g_object_unref(method_call);
        }).detach();

    // ---- convertToM4a ----
    } else if (strcmp(method, "convertToM4a") == 0) {
        if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
            send_error(method_call, "INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        FlValue* inputVal = fl_value_lookup_string(args, "inputPath");
        FlValue* outputVal = fl_value_lookup_string(args, "outputPath");
        if (!inputVal || !outputVal) {
            send_error(method_call, "INVALID_ARGUMENTS",
                       "inputPath and outputPath are required");
            return;
        }
        std::string inputPath = fl_value_get_string(inputVal);
        std::string outputPath = fl_value_get_string(outputVal);

        g_object_ref(method_call);
        std::thread([method_call, inputPath, outputPath]() {
            try {
                std::string result = ConvertToM4a(inputPath, outputPath);
                g_autoptr(FlValue) val = fl_value_new_string(result.c_str());
                send_success(method_call, val);
            } catch (const std::exception& e) {
                send_error(method_call, "CONVERSION_ERROR", e.what());
            }
            g_object_unref(method_call);
        }).detach();

    // ---- getAudioInfo ----
    } else if (strcmp(method, "getAudioInfo") == 0) {
        if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
            send_error(method_call, "INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        FlValue* pathVal = fl_value_lookup_string(args, "path");
        if (!pathVal) {
            send_error(method_call, "INVALID_ARGUMENTS", "path is required");
            return;
        }
        std::string path = fl_value_get_string(pathVal);

        g_object_ref(method_call);
        std::thread([method_call, path]() {
            try {
                g_autoptr(FlValue) info = GetAudioInfo(path);
                send_success(method_call, info);
            } catch (const std::exception& e) {
                send_error(method_call, "INFO_ERROR", e.what());
            }
            g_object_unref(method_call);
        }).detach();

    // ---- trimAudio ----
    } else if (strcmp(method, "trimAudio") == 0) {
        if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
            send_error(method_call, "INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        FlValue* inputVal = fl_value_lookup_string(args, "inputPath");
        FlValue* outputVal = fl_value_lookup_string(args, "outputPath");
        FlValue* startVal = fl_value_lookup_string(args, "startMs");
        FlValue* endVal = fl_value_lookup_string(args, "endMs");
        if (!inputVal || !outputVal || !startVal || !endVal) {
            send_error(method_call, "INVALID_ARGUMENTS",
                       "inputPath, outputPath, startMs and endMs are required");
            return;
        }
        std::string inputPath = fl_value_get_string(inputVal);
        std::string outputPath = fl_value_get_string(outputVal);
        int64_t startMs = fl_value_get_int(startVal);
        int64_t endMs = fl_value_get_int(endVal);

        g_object_ref(method_call);
        std::thread([method_call, inputPath, outputPath, startMs, endMs]() {
            try {
                std::string result =
                    TrimAudio(inputPath, outputPath, startMs, endMs);
                g_autoptr(FlValue) val = fl_value_new_string(result.c_str());
                send_success(method_call, val);
            } catch (const std::exception& e) {
                send_error(method_call, "TRIM_ERROR", e.what());
            }
            g_object_unref(method_call);
        }).detach();

    // ---- getWaveform ----
    } else if (strcmp(method, "getWaveform") == 0) {
        if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
            send_error(method_call, "INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        FlValue* pathVal = fl_value_lookup_string(args, "path");
        FlValue* samplesVal = fl_value_lookup_string(args, "numberOfSamples");
        if (!pathVal || !samplesVal) {
            send_error(method_call, "INVALID_ARGUMENTS",
                       "path and numberOfSamples are required");
            return;
        }
        std::string path = fl_value_get_string(pathVal);
        int numberOfSamples = static_cast<int>(fl_value_get_int(samplesVal));

        g_object_ref(method_call);
        std::thread([method_call, path, numberOfSamples]() {
            try {
                g_autoptr(FlValue) waveform = GetWaveform(path, numberOfSamples);
                send_success(method_call, waveform);
            } catch (const std::exception& e) {
                send_error(method_call, "WAVEFORM_ERROR", e.what());
            }
            g_object_unref(method_call);
        }).detach();

    // ---- convertToWavBytes ----
    } else if (strcmp(method, "convertToWavBytes") == 0) {
        if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
            send_error(method_call, "INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        FlValue* dataVal = fl_value_lookup_string(args, "inputData");
        FlValue* hintVal = fl_value_lookup_string(args, "formatHint");
        if (!dataVal || !hintVal) {
            send_error(method_call, "INVALID_ARGUMENTS",
                       "inputData and formatHint are required");
            return;
        }
        const uint8_t* rawData = fl_value_get_uint8_list(dataVal);
        size_t dataLen = fl_value_get_length(dataVal);
        std::vector<uint8_t> inputData(rawData, rawData + dataLen);
        std::string formatHint = fl_value_get_string(hintVal);

        int targetSampleRate = -1, targetChannels = -1, targetBitDepth = -1;
        FlValue* srVal = fl_value_lookup_string(args, "sampleRate");
        if (srVal && fl_value_get_type(srVal) == FL_VALUE_TYPE_INT)
            targetSampleRate = static_cast<int>(fl_value_get_int(srVal));
        FlValue* chVal = fl_value_lookup_string(args, "channels");
        if (chVal && fl_value_get_type(chVal) == FL_VALUE_TYPE_INT)
            targetChannels = static_cast<int>(fl_value_get_int(chVal));
        FlValue* bdVal = fl_value_lookup_string(args, "bitDepth");
        if (bdVal && fl_value_get_type(bdVal) == FL_VALUE_TYPE_INT)
            targetBitDepth = static_cast<int>(fl_value_get_int(bdVal));

        g_object_ref(method_call);
        std::thread([method_call, inputData = std::move(inputData), formatHint, targetSampleRate, targetChannels, targetBitDepth]() {
            try {
                std::string tempInput = WriteTempFile(inputData, formatHint);
                std::string tempOutput = WriteTempFile({}, "wav");
                try {
                    ConvertToWav(tempInput, tempOutput, targetSampleRate, targetChannels, targetBitDepth);
                    auto outputBytes = ReadAndDeleteFile(tempOutput);
                    std::remove(tempInput.c_str());
                    g_autoptr(FlValue) val = fl_value_new_uint8_list(
                        outputBytes.data(), outputBytes.size());
                    send_success(method_call, val);
                } catch (...) {
                    std::remove(tempInput.c_str());
                    std::remove(tempOutput.c_str());
                    throw;
                }
            } catch (const std::exception& e) {
                send_error(method_call, "CONVERSION_ERROR", e.what());
            }
            g_object_unref(method_call);
        }).detach();

    // ---- convertToM4aBytes ----
    } else if (strcmp(method, "convertToM4aBytes") == 0) {
        if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
            send_error(method_call, "INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        FlValue* dataVal = fl_value_lookup_string(args, "inputData");
        FlValue* hintVal = fl_value_lookup_string(args, "formatHint");
        if (!dataVal || !hintVal) {
            send_error(method_call, "INVALID_ARGUMENTS",
                       "inputData and formatHint are required");
            return;
        }
        const uint8_t* rawData = fl_value_get_uint8_list(dataVal);
        size_t dataLen = fl_value_get_length(dataVal);
        std::vector<uint8_t> inputData(rawData, rawData + dataLen);
        std::string formatHint = fl_value_get_string(hintVal);

        g_object_ref(method_call);
        std::thread([method_call, inputData = std::move(inputData), formatHint]() {
            try {
                std::string tempInput = WriteTempFile(inputData, formatHint);
                std::string tempOutput = WriteTempFile({}, "m4a");
                try {
                    ConvertToM4a(tempInput, tempOutput);
                    auto outputBytes = ReadAndDeleteFile(tempOutput);
                    std::remove(tempInput.c_str());
                    g_autoptr(FlValue) val = fl_value_new_uint8_list(
                        outputBytes.data(), outputBytes.size());
                    send_success(method_call, val);
                } catch (...) {
                    std::remove(tempInput.c_str());
                    std::remove(tempOutput.c_str());
                    throw;
                }
            } catch (const std::exception& e) {
                send_error(method_call, "CONVERSION_ERROR", e.what());
            }
            g_object_unref(method_call);
        }).detach();

    // ---- getAudioInfoBytes ----
    } else if (strcmp(method, "getAudioInfoBytes") == 0) {
        if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
            send_error(method_call, "INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        FlValue* dataVal = fl_value_lookup_string(args, "inputData");
        FlValue* hintVal = fl_value_lookup_string(args, "formatHint");
        if (!dataVal || !hintVal) {
            send_error(method_call, "INVALID_ARGUMENTS",
                       "inputData and formatHint are required");
            return;
        }
        const uint8_t* rawData = fl_value_get_uint8_list(dataVal);
        size_t dataLen = fl_value_get_length(dataVal);
        std::vector<uint8_t> inputData(rawData, rawData + dataLen);
        std::string formatHint = fl_value_get_string(hintVal);

        g_object_ref(method_call);
        std::thread([method_call, inputData = std::move(inputData), formatHint]() {
            try {
                std::string tempInput = WriteTempFile(inputData, formatHint);
                try {
                    g_autoptr(FlValue) info = GetAudioInfo(tempInput);
                    std::remove(tempInput.c_str());
                    send_success(method_call, info);
                } catch (...) {
                    std::remove(tempInput.c_str());
                    throw;
                }
            } catch (const std::exception& e) {
                send_error(method_call, "INFO_ERROR", e.what());
            }
            g_object_unref(method_call);
        }).detach();

    // ---- trimAudioBytes ----
    } else if (strcmp(method, "trimAudioBytes") == 0) {
        if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
            send_error(method_call, "INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        FlValue* dataVal = fl_value_lookup_string(args, "inputData");
        FlValue* hintVal = fl_value_lookup_string(args, "formatHint");
        FlValue* startVal = fl_value_lookup_string(args, "startMs");
        FlValue* endVal = fl_value_lookup_string(args, "endMs");
        if (!dataVal || !hintVal || !startVal || !endVal) {
            send_error(method_call, "INVALID_ARGUMENTS",
                       "inputData, formatHint, startMs and endMs are required");
            return;
        }
        const uint8_t* rawData = fl_value_get_uint8_list(dataVal);
        size_t dataLen = fl_value_get_length(dataVal);
        std::vector<uint8_t> inputData(rawData, rawData + dataLen);
        std::string formatHint = fl_value_get_string(hintVal);
        int64_t startMs = fl_value_get_int(startVal);
        int64_t endMs = fl_value_get_int(endVal);

        FlValue* fmtVal = fl_value_lookup_string(args, "outputFormat");
        std::string outputFormat =
            (fmtVal && fl_value_get_type(fmtVal) == FL_VALUE_TYPE_STRING)
                ? fl_value_get_string(fmtVal) : "wav";

        g_object_ref(method_call);
        std::thread([method_call, inputData = std::move(inputData), formatHint,
                     startMs, endMs, outputFormat]() {
            try {
                std::string tempInput = WriteTempFile(inputData, formatHint);
                std::string tempOutput = WriteTempFile({}, outputFormat);
                try {
                    TrimAudio(tempInput, tempOutput, startMs, endMs);
                    auto outputBytes = ReadAndDeleteFile(tempOutput);
                    std::remove(tempInput.c_str());
                    g_autoptr(FlValue) val = fl_value_new_uint8_list(
                        outputBytes.data(), outputBytes.size());
                    send_success(method_call, val);
                } catch (...) {
                    std::remove(tempInput.c_str());
                    std::remove(tempOutput.c_str());
                    throw;
                }
            } catch (const std::exception& e) {
                send_error(method_call, "TRIM_ERROR", e.what());
            }
            g_object_unref(method_call);
        }).detach();

    // ---- getWaveformBytes ----
    } else if (strcmp(method, "getWaveformBytes") == 0) {
        if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
            send_error(method_call, "INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        FlValue* dataVal = fl_value_lookup_string(args, "inputData");
        FlValue* hintVal = fl_value_lookup_string(args, "formatHint");
        FlValue* samplesVal = fl_value_lookup_string(args, "numberOfSamples");
        if (!dataVal || !hintVal || !samplesVal) {
            send_error(method_call, "INVALID_ARGUMENTS",
                       "inputData, formatHint and numberOfSamples are required");
            return;
        }
        const uint8_t* rawData = fl_value_get_uint8_list(dataVal);
        size_t dataLen = fl_value_get_length(dataVal);
        std::vector<uint8_t> inputData(rawData, rawData + dataLen);
        std::string formatHint = fl_value_get_string(hintVal);
        int numberOfSamples = static_cast<int>(fl_value_get_int(samplesVal));

        g_object_ref(method_call);
        std::thread([method_call, inputData = std::move(inputData), formatHint,
                     numberOfSamples]() {
            try {
                std::string tempInput = WriteTempFile(inputData, formatHint);
                try {
                    g_autoptr(FlValue) waveform =
                        GetWaveform(tempInput, numberOfSamples);
                    std::remove(tempInput.c_str());
                    send_success(method_call, waveform);
                } catch (...) {
                    std::remove(tempInput.c_str());
                    throw;
                }
            } catch (const std::exception& e) {
                send_error(method_call, "WAVEFORM_ERROR", e.what());
            }
            g_object_unref(method_call);
        }).detach();

    } else {
        g_autoptr(FlMethodResponse) response =
            FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
        fl_method_call_respond(method_call, response, nullptr);
    }
}

// ---------------------------------------------------------------------------
// GObject lifecycle
// ---------------------------------------------------------------------------

static void audio_decoder_plugin_dispose(GObject* object) {
    AudioDecoderPlugin* self = AUDIO_DECODER_PLUGIN(object);
    g_clear_object(&self->channel);
    G_OBJECT_CLASS(audio_decoder_plugin_parent_class)->dispose(object);
}

static void audio_decoder_plugin_class_init(AudioDecoderPluginClass* klass) {
    G_OBJECT_CLASS(klass)->dispose = audio_decoder_plugin_dispose;
}

static void audio_decoder_plugin_init(AudioDecoderPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
    AudioDecoderPlugin* plugin = AUDIO_DECODER_PLUGIN(user_data);
    handle_method_call(plugin, method_call);
}

void audio_decoder_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
    // Initialize GStreamer
    gst_init(nullptr, nullptr);

    AudioDecoderPlugin* plugin = AUDIO_DECODER_PLUGIN(
        g_object_new(audio_decoder_plugin_get_type(), nullptr));

    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    plugin->channel = fl_method_channel_new(
        fl_plugin_registrar_get_messenger(registrar), "audio_decoder",
        FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(
        plugin->channel, method_call_cb, g_object_ref(plugin), g_object_unref);

    g_object_unref(plugin);
}
