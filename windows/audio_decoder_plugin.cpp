#include "audio_decoder_plugin.h"

#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>
#include <thread>
#include <functional>
#include <cmath>
#include <algorithm>
#include <cctype>
#include <stdexcept>

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "mf.lib")

/// Standard RIFF/WAV header size in bytes (no extra chunks).
static constexpr size_t kWavHeaderSize = 44;

/// Maximum PCM data size that fits in a standard WAV file (~4 GB).
static constexpr int64_t kMaxWavDataSize = 0xFFFFFFFFL - 36;

/// Media Foundation expresses time in 100-nanosecond units ("hns").
static constexpr int64_t kHnsPerMs = 10000LL;
static constexpr int64_t kHnsPerSec = 10000000LL;

static std::wstring Utf8ToWide(const std::string& utf8) {
    if (utf8.empty()) return {};
    int size = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
    std::wstring wide(size - 1, 0);
    MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, &wide[0], size);
    return wide;
}

static std::string WideToUtf8(const std::wstring& wide) {
    if (wide.empty()) return {};
    int size = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, nullptr, 0, nullptr, nullptr);
    std::string utf8(size - 1, 0);
    WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, &utf8[0], size, nullptr, nullptr);
    return utf8;
}

class MFSession {
public:
    MFSession() : initialized_(false) {
        HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        if (SUCCEEDED(hr) || hr == S_FALSE) {
            hr = MFStartup(MF_VERSION);
            initialized_ = SUCCEEDED(hr);
        }
    }
    ~MFSession() {
        if (initialized_) {
            MFShutdown();
        }
        CoUninitialize();
    }
    bool IsInitialized() const { return initialized_; }
private:
    bool initialized_;
};

/// Streams 16-bit PCM into an AAC/M4A file through IMFSinkWriter.
///
/// Begin() is called once the PCM format is known — which is only after the
/// source reader has been configured — after which every decoded buffer can be
/// handed to WriteChunk() directly, so the audio never has to be buffered in
/// full.
class M4aStreamWriter {
public:
    explicit M4aStreamWriter(const std::string& outputPath)
            : wOutputPath_(Utf8ToWide(outputPath)) {
        DeleteFileW(wOutputPath_.c_str());
    }

    ~M4aStreamWriter() { Release(); }

    M4aStreamWriter(const M4aStreamWriter&) = delete;
    M4aStreamWriter& operator=(const M4aStreamWriter&) = delete;

    void Begin(uint32_t sampleRate, uint32_t channels) {
        if (sampleRate == 0 || channels == 0) {
            throw std::runtime_error("Input reports an unusable PCM format");
        }
        blockAlign_ = static_cast<int64_t>(channels) * 2;
        bytesPerSec_ = static_cast<int64_t>(sampleRate) * blockAlign_;

        HRESULT hr = MFCreateSinkWriterFromURL(wOutputPath_.c_str(), nullptr,
                                               nullptr, &pWriter_);
        if (FAILED(hr)) {
            throw std::runtime_error("Failed to create sink writer");
        }

        IMFMediaType* pAacType = nullptr;
        MFCreateMediaType(&pAacType);
        pAacType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
        pAacType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
        pAacType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, sampleRate);
        pAacType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, channels);
        pAacType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
        pAacType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 128000 / 8);

        hr = pWriter_->AddStream(pAacType, &streamIndex_);
        pAacType->Release();
        if (FAILED(hr)) {
            Release();
            throw std::runtime_error("Failed to add AAC stream");
        }

        IMFMediaType* pInputType = nullptr;
        MFCreateMediaType(&pInputType);
        pInputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
        pInputType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
        pInputType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, sampleRate);
        pInputType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, channels);
        pInputType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
        pInputType->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT,
                              static_cast<UINT32>(blockAlign_));
        pInputType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND,
                              static_cast<UINT32>(bytesPerSec_));

        hr = pWriter_->SetInputMediaType(streamIndex_, pInputType, nullptr);
        pInputType->Release();
        if (FAILED(hr)) {
            Release();
            throw std::runtime_error("Failed to set input type");
        }

        hr = pWriter_->BeginWriting();
        if (FAILED(hr)) {
            Release();
            throw std::runtime_error("Failed to begin writing");
        }
        started_ = true;
    }

    void WriteChunk(const uint8_t* data, size_t size) {
        if (!started_) {
            throw std::runtime_error("Sink writer was not initialized");
        }
        if (size == 0) return;

        IMFMediaBuffer* pBuffer = nullptr;
        HRESULT hr = MFCreateMemoryBuffer(static_cast<DWORD>(size), &pBuffer);
        if (FAILED(hr)) {
            throw std::runtime_error("Failed to allocate encoder buffer");
        }

        BYTE* pBufData = nullptr;
        hr = pBuffer->Lock(&pBufData, nullptr, nullptr);
        if (FAILED(hr)) {
            pBuffer->Release();
            throw std::runtime_error("Failed to lock encoder buffer");
        }
        memcpy(pBufData, data, size);
        pBuffer->Unlock();
        pBuffer->SetCurrentLength(static_cast<DWORD>(size));

        IMFSample* pSample = nullptr;
        hr = MFCreateSample(&pSample);
        if (FAILED(hr)) {
            pBuffer->Release();
            throw std::runtime_error("Failed to create encoder sample");
        }
        pSample->AddBuffer(pBuffer);
        // Derive timestamps from the running byte count instead of summing
        // per-chunk durations, which would drift on long recordings.
        pSample->SetSampleTime(bytesWritten_ * kHnsPerSec / bytesPerSec_);
        pSample->SetSampleDuration(
            static_cast<LONGLONG>(size) * kHnsPerSec / bytesPerSec_);

        hr = pWriter_->WriteSample(streamIndex_, pSample);
        pSample->Release();
        pBuffer->Release();
        if (FAILED(hr)) {
            throw std::runtime_error("Failed to write audio sample");
        }
        bytesWritten_ += static_cast<int64_t>(size);
    }

    void Finish() {
        if (!started_) {
            throw std::runtime_error("Sink writer was not initialized");
        }
        HRESULT hr = pWriter_->Finalize();
        Release();
        if (FAILED(hr)) {
            DeleteFileW(wOutputPath_.c_str());
            throw std::runtime_error("Failed to finalize M4A output");
        }
    }

    /// Releases the writer and removes a partially written output file.
    void Abort() {
        Release();
        DeleteFileW(wOutputPath_.c_str());
    }

private:
    void Release() {
        if (pWriter_) {
            pWriter_->Release();
            pWriter_ = nullptr;
        }
        started_ = false;
    }

    std::wstring wOutputPath_;
    IMFSinkWriter* pWriter_ = nullptr;
    DWORD streamIndex_ = 0;
    int64_t blockAlign_ = 0;
    int64_t bytesPerSec_ = 0;
    int64_t bytesWritten_ = 0;
    bool started_ = false;
};

/// Accumulates RMS energy for a waveform while the audio is still decoding.
///
/// Keeping every decoded sample is not an option — three hours of 44.1 kHz
/// stereo audio is close to a billion samples — so energy is folded into a
/// fixed set of buckets instead.  Each bucket covers samplesPerBucket_
/// consecutive samples; once the arrays are full, adjacent buckets are merged
/// pairwise and the span per bucket doubles.  Memory therefore stays bounded
/// regardless of duration, while short inputs (which never trigger a merge) are
/// summarized sample-exact.
///
/// The window bounds in Build() are computed with 64-bit arithmetic on purpose:
/// for longer files the product `i * totalSamples` easily exceeds a 32-bit
/// integer, which would wrap to a negative offset.  The caller is expected to
/// validate the normalization mode beforehand.
class WaveformAccumulator {
public:
    explicit WaveformAccumulator(int numberOfSamples)
            : numberOfSamples_(numberOfSamples) {
        // Aim for kBucketsPerWindow buckets per output point so window bounds
        // land close to a bucket edge, keeping the RMS error negligible once
        // merging kicks in.
        int64_t target = static_cast<int64_t>(numberOfSamples) * kBucketsPerWindow;
        int64_t capacity = (std::min)((std::max)(target, kMinBuckets), kMaxBuckets);
        // An even capacity keeps pairwise merging exact.
        if (capacity % 2 != 0) capacity++;
        sumSquares_.resize(static_cast<size_t>(capacity), 0.0);
        counts_.resize(static_cast<size_t>(capacity), 0);
    }

    /// Adds a chunk of interleaved little-endian 16-bit PCM.  A sample split
    /// across two chunks is carried over instead of dropped.
    void AddPcm(const uint8_t* data, size_t size) {
        size_t offset = 0;
        if (hasPendingByte_ && size > 0) {
            Add(static_cast<int16_t>(static_cast<uint16_t>(pendingByte_) |
                                     (static_cast<uint16_t>(data[0]) << 8)));
            hasPendingByte_ = false;
            offset = 1;
        }
        for (; offset + 1 < size; offset += 2) {
            Add(static_cast<int16_t>(static_cast<uint16_t>(data[offset]) |
                                     (static_cast<uint16_t>(data[offset + 1]) << 8)));
        }
        if (offset < size) {
            pendingByte_ = data[offset];
            hasPendingByte_ = true;
        }
    }

    /// Builds the normalized waveform from everything accumulated so far.
    std::vector<double> Build(const std::string& normalization) const {
        if (totalSamples_ == 0) {
            return std::vector<double>(static_cast<size_t>(numberOfSamples_), 0.0);
        }

        int64_t windowSize = (std::max)(static_cast<int64_t>(1),
                                        totalSamples_ / numberOfSamples_);
        std::vector<double> waveform;
        double maxRms = 0;

        for (int i = 0; i < numberOfSamples_; i++) {
            int64_t start = static_cast<int64_t>(i) * totalSamples_ / numberOfSamples_;
            if (start >= totalSamples_) break;
            int64_t end = (std::min)(start + windowSize, totalSamples_);

            double rms = std::sqrt(SumSquaresIn(start, end) /
                                   static_cast<double>(end - start));
            waveform.push_back(rms);
            if (rms > maxRms) maxRms = rms;
        }

        // Samples are signed 16-bit PCM with range [-32768, 32767], so absolute
        // mode divides by the max magnitude (32768) to keep the result inside
        // [0.0, 1.0] even when a window is filled with -32768.
        const bool useAbsolute = (normalization == "absolute");
        std::vector<double> result;
        result.reserve(static_cast<size_t>(numberOfSamples_));
        for (double value : waveform) {
            result.push_back(useAbsolute ? value / 32768.0
                                         : ((maxRms > 0) ? value / maxRms : 0.0));
        }
        // Pad if the audio was shorter than the requested resolution.
        result.resize(static_cast<size_t>(numberOfSamples_), 0.0);
        return result;
    }

private:
    static constexpr int64_t kBucketsPerWindow = 256;
    static constexpr int64_t kMinBuckets = 1024;

    /// Caps the accumulator at ~4 MB (one double plus one int64 per bucket).
    static constexpr int64_t kMaxBuckets = 262144;

    void Add(int16_t sample) {
        if (bucketCount_ == 0 || counts_[bucketCount_ - 1] >= samplesPerBucket_) {
            if (bucketCount_ == counts_.size()) MergeAdjacentBuckets();
            bucketCount_++;
            sumSquares_[bucketCount_ - 1] = 0.0;
            counts_[bucketCount_ - 1] = 0;
        }
        double value = static_cast<double>(sample);
        sumSquares_[bucketCount_ - 1] += value * value;
        counts_[bucketCount_ - 1]++;
        totalSamples_++;
    }

    /// Halves the resolution so more samples fit in the same arrays.
    void MergeAdjacentBuckets() {
        size_t dst = 0;
        for (size_t src = 0; src < bucketCount_; src += 2) {
            sumSquares_[dst] = sumSquares_[src] + sumSquares_[src + 1];
            counts_[dst] = counts_[src] + counts_[src + 1];
            dst++;
        }
        bucketCount_ = dst;
        samplesPerBucket_ *= 2;
    }

    /// Sum of squares over the sample range [start, end).
    double SumSquaresIn(int64_t start, int64_t end) const {
        double sum = 0;
        // Every bucket but the last is full, so bucket b starts at
        // b * samplesPerBucket_.
        size_t bucket = static_cast<size_t>(start / samplesPerBucket_);
        for (; bucket < bucketCount_; bucket++) {
            int64_t bucketStart = static_cast<int64_t>(bucket) * samplesPerBucket_;
            if (bucketStart >= end) break;
            int64_t bucketEnd = bucketStart + counts_[bucket];
            int64_t overlap =
                (std::min)(end, bucketEnd) - (std::max)(start, bucketStart);
            if (overlap <= 0) continue;
            if (overlap >= counts_[bucket]) {
                sum += sumSquares_[bucket];
            } else {
                // Partial overlap: assume the energy is spread evenly across
                // the bucket.
                sum += sumSquares_[bucket] * static_cast<double>(overlap) /
                       static_cast<double>(counts_[bucket]);
            }
        }
        return sum;
    }

    int numberOfSamples_;
    std::vector<double> sumSquares_;
    std::vector<int64_t> counts_;

    /// Number of samples each full bucket covers; doubles on every merge.
    int64_t samplesPerBucket_ = 1;
    size_t bucketCount_ = 0;
    int64_t totalSamples_ = 0;
    uint8_t pendingByte_ = 0;
    bool hasPendingByte_ = false;
};

namespace audio_decoder {

void AudioDecoderPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "audio_decoder",
            &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<AudioDecoderPlugin>();

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result) {
            plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
}

AudioDecoderPlugin::AudioDecoderPlugin() {}

AudioDecoderPlugin::~AudioDecoderPlugin() {}

void AudioDecoderPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());

    if (method_call.method_name() == "convertToWav") {
        if (!args) {
            result->Error("INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        auto inputIt = args->find(flutter::EncodableValue("inputPath"));
        auto outputIt = args->find(flutter::EncodableValue("outputPath"));
        if (inputIt == args->end() || outputIt == args->end()) {
            result->Error("INVALID_ARGUMENTS", "inputPath and outputPath are required");
            return;
        }
        std::string inputPath = std::get<std::string>(inputIt->second);
        std::string outputPath = std::get<std::string>(outputIt->second);

        int targetSampleRate = -1, targetChannels = -1, targetBitDepth = -1;
        auto srIt = args->find(flutter::EncodableValue("sampleRate"));
        if (srIt != args->end()) targetSampleRate = std::get<int32_t>(srIt->second);
        auto chIt = args->find(flutter::EncodableValue("channels"));
        if (chIt != args->end()) targetChannels = std::get<int32_t>(chIt->second);
        auto bdIt = args->find(flutter::EncodableValue("bitDepth"));
        if (bdIt != args->end()) targetBitDepth = std::get<int32_t>(bdIt->second);

        auto shared_result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
            std::move(result));
        std::thread([this, inputPath, outputPath, targetSampleRate, targetChannels, targetBitDepth, shared_result]() {
            try {
                std::string output = ConvertToWav(inputPath, outputPath, targetSampleRate, targetChannels, targetBitDepth);
                shared_result->Success(flutter::EncodableValue(output));
            } catch (const std::exception& e) {
                shared_result->Error("CONVERSION_ERROR", e.what());
            }
        }).detach();

    } else if (method_call.method_name() == "convertToM4a") {
        if (!args) {
            result->Error("INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        auto inputIt = args->find(flutter::EncodableValue("inputPath"));
        auto outputIt = args->find(flutter::EncodableValue("outputPath"));
        if (inputIt == args->end() || outputIt == args->end()) {
            result->Error("INVALID_ARGUMENTS", "inputPath and outputPath are required");
            return;
        }
        std::string inputPath = std::get<std::string>(inputIt->second);
        std::string outputPath = std::get<std::string>(outputIt->second);

        auto shared_result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
            std::move(result));
        std::thread([this, inputPath, outputPath, shared_result]() {
            try {
                std::string output = ConvertToM4a(inputPath, outputPath);
                shared_result->Success(flutter::EncodableValue(output));
            } catch (const std::exception& e) {
                shared_result->Error("CONVERSION_ERROR", e.what());
            }
        }).detach();

    } else if (method_call.method_name() == "getAudioInfo") {
        if (!args) {
            result->Error("INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        auto pathIt = args->find(flutter::EncodableValue("path"));
        if (pathIt == args->end()) {
            result->Error("INVALID_ARGUMENTS", "path is required");
            return;
        }
        std::string path = std::get<std::string>(pathIt->second);

        auto shared_result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
            std::move(result));
        std::thread([this, path, shared_result]() {
            try {
                auto info = GetAudioInfo(path);
                shared_result->Success(flutter::EncodableValue(info));
            } catch (const std::exception& e) {
                shared_result->Error("INFO_ERROR", e.what());
            }
        }).detach();

    } else if (method_call.method_name() == "trimAudio") {
        if (!args) {
            result->Error("INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        auto inputIt = args->find(flutter::EncodableValue("inputPath"));
        auto outputIt = args->find(flutter::EncodableValue("outputPath"));
        auto startIt = args->find(flutter::EncodableValue("startMs"));
        auto endIt = args->find(flutter::EncodableValue("endMs"));
        if (inputIt == args->end() || outputIt == args->end() ||
            startIt == args->end() || endIt == args->end()) {
            result->Error("INVALID_ARGUMENTS", "inputPath, outputPath, startMs and endMs are required");
            return;
        }
        std::string inputPath = std::get<std::string>(inputIt->second);
        std::string outputPath = std::get<std::string>(outputIt->second);
        int64_t startMs = std::get<int32_t>(startIt->second);
        int64_t endMs = std::get<int32_t>(endIt->second);

        auto shared_result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
            std::move(result));
        std::thread([this, inputPath, outputPath, startMs, endMs, shared_result]() {
            try {
                std::string output = TrimAudio(inputPath, outputPath, startMs, endMs);
                shared_result->Success(flutter::EncodableValue(output));
            } catch (const std::exception& e) {
                shared_result->Error("TRIM_ERROR", e.what());
            }
        }).detach();

    } else if (method_call.method_name() == "getWaveform") {
        if (!args) {
            result->Error("INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        auto pathIt = args->find(flutter::EncodableValue("path"));
        auto samplesIt = args->find(flutter::EncodableValue("numberOfSamples"));
        if (pathIt == args->end() || samplesIt == args->end()) {
            result->Error("INVALID_ARGUMENTS", "path and numberOfSamples are required");
            return;
        }
        std::string path = std::get<std::string>(pathIt->second);
        int numberOfSamples = std::get<int32_t>(samplesIt->second);
        std::string normalization = "perFile";
        auto normIt = args->find(flutter::EncodableValue("normalization"));
        if (normIt != args->end()) {
            if (auto* s = std::get_if<std::string>(&normIt->second)) {
                normalization = *s;
            }
        }

        auto shared_result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
            std::move(result));
        std::thread([this, path, numberOfSamples, normalization, shared_result]() {
            try {
                auto waveform = GetWaveform(path, numberOfSamples, normalization);
                shared_result->Success(flutter::EncodableValue(waveform));
            } catch (const std::exception& e) {
                shared_result->Error("WAVEFORM_ERROR", e.what());
            }
        }).detach();

    } else if (method_call.method_name() == "convertToWavBytes") {
        if (!args) {
            result->Error("INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        auto dataIt = args->find(flutter::EncodableValue("inputData"));
        auto hintIt = args->find(flutter::EncodableValue("formatHint"));
        if (dataIt == args->end() || hintIt == args->end()) {
            result->Error("INVALID_ARGUMENTS", "inputData and formatHint are required");
            return;
        }
        auto inputData = std::get<std::vector<uint8_t>>(dataIt->second);
        std::string formatHint = std::get<std::string>(hintIt->second);

        int targetSampleRate = -1, targetChannels = -1, targetBitDepth = -1;
        auto srIt = args->find(flutter::EncodableValue("sampleRate"));
        if (srIt != args->end()) targetSampleRate = std::get<int32_t>(srIt->second);
        auto chIt = args->find(flutter::EncodableValue("channels"));
        if (chIt != args->end()) targetChannels = std::get<int32_t>(chIt->second);
        auto bdIt = args->find(flutter::EncodableValue("bitDepth"));
        if (bdIt != args->end()) targetBitDepth = std::get<int32_t>(bdIt->second);

        bool includeHeader = true;
        auto headerIt = args->find(flutter::EncodableValue("includeHeader"));
        if (headerIt != args->end()) includeHeader = std::get<bool>(headerIt->second);

        auto shared_result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
            std::move(result));
        std::thread([this, inputData = std::move(inputData), formatHint, targetSampleRate, targetChannels, targetBitDepth, includeHeader, shared_result]() {
            try {
                std::string tempInput = WriteTempFile(inputData, formatHint);
                std::string tempOutput = WriteTempFile({}, "wav");
                try {
                    ConvertToWav(tempInput, tempOutput, targetSampleRate, targetChannels, targetBitDepth);
                    auto outputBytes = ReadAndDeleteFile(tempOutput);
                    DeleteFileW(Utf8ToWide(tempInput).c_str());
                    // Strip the WAV header to return raw PCM.
                    if (!includeHeader && outputBytes.size() >= kWavHeaderSize) {
                        outputBytes.erase(outputBytes.begin(), outputBytes.begin() + kWavHeaderSize);
                    }
                    shared_result->Success(flutter::EncodableValue(outputBytes));
                } catch (...) {
                    DeleteFileW(Utf8ToWide(tempInput).c_str());
                    DeleteFileW(Utf8ToWide(tempOutput).c_str());
                    throw;
                }
            } catch (const std::exception& e) {
                shared_result->Error("CONVERSION_ERROR", e.what());
            }
        }).detach();

    } else if (method_call.method_name() == "convertToM4aBytes") {
        if (!args) {
            result->Error("INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        auto dataIt = args->find(flutter::EncodableValue("inputData"));
        auto hintIt = args->find(flutter::EncodableValue("formatHint"));
        if (dataIt == args->end() || hintIt == args->end()) {
            result->Error("INVALID_ARGUMENTS", "inputData and formatHint are required");
            return;
        }
        auto inputData = std::get<std::vector<uint8_t>>(dataIt->second);
        std::string formatHint = std::get<std::string>(hintIt->second);

        auto shared_result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
            std::move(result));
        std::thread([this, inputData = std::move(inputData), formatHint, shared_result]() {
            try {
                std::string tempInput = WriteTempFile(inputData, formatHint);
                std::string tempOutput = WriteTempFile({}, "m4a");
                try {
                    ConvertToM4a(tempInput, tempOutput);
                    auto outputBytes = ReadAndDeleteFile(tempOutput);
                    DeleteFileW(Utf8ToWide(tempInput).c_str());
                    shared_result->Success(flutter::EncodableValue(outputBytes));
                } catch (...) {
                    DeleteFileW(Utf8ToWide(tempInput).c_str());
                    DeleteFileW(Utf8ToWide(tempOutput).c_str());
                    throw;
                }
            } catch (const std::exception& e) {
                shared_result->Error("CONVERSION_ERROR", e.what());
            }
        }).detach();

    } else if (method_call.method_name() == "getAudioInfoBytes") {
        if (!args) {
            result->Error("INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        auto dataIt = args->find(flutter::EncodableValue("inputData"));
        auto hintIt = args->find(flutter::EncodableValue("formatHint"));
        if (dataIt == args->end() || hintIt == args->end()) {
            result->Error("INVALID_ARGUMENTS", "inputData and formatHint are required");
            return;
        }
        auto inputData = std::get<std::vector<uint8_t>>(dataIt->second);
        std::string formatHint = std::get<std::string>(hintIt->second);

        auto shared_result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
            std::move(result));
        std::thread([this, inputData = std::move(inputData), formatHint, shared_result]() {
            try {
                std::string tempInput = WriteTempFile(inputData, formatHint);
                try {
                    auto info = GetAudioInfo(tempInput);
                    DeleteFileW(Utf8ToWide(tempInput).c_str());
                    shared_result->Success(flutter::EncodableValue(info));
                } catch (...) {
                    DeleteFileW(Utf8ToWide(tempInput).c_str());
                    throw;
                }
            } catch (const std::exception& e) {
                shared_result->Error("INFO_ERROR", e.what());
            }
        }).detach();

    } else if (method_call.method_name() == "trimAudioBytes") {
        if (!args) {
            result->Error("INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        auto dataIt = args->find(flutter::EncodableValue("inputData"));
        auto hintIt = args->find(flutter::EncodableValue("formatHint"));
        auto startIt = args->find(flutter::EncodableValue("startMs"));
        auto endIt = args->find(flutter::EncodableValue("endMs"));
        auto fmtIt = args->find(flutter::EncodableValue("outputFormat"));
        if (dataIt == args->end() || hintIt == args->end() ||
            startIt == args->end() || endIt == args->end()) {
            result->Error("INVALID_ARGUMENTS", "inputData, formatHint, startMs and endMs are required");
            return;
        }
        auto inputData = std::get<std::vector<uint8_t>>(dataIt->second);
        std::string formatHint = std::get<std::string>(hintIt->second);
        int64_t startMs = std::get<int32_t>(startIt->second);
        int64_t endMs = std::get<int32_t>(endIt->second);
        std::string outputFormat = (fmtIt != args->end()) ? std::get<std::string>(fmtIt->second) : "wav";

        auto shared_result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
            std::move(result));
        std::thread([this, inputData = std::move(inputData), formatHint, startMs, endMs, outputFormat, shared_result]() {
            try {
                std::string tempInput = WriteTempFile(inputData, formatHint);
                std::string tempOutput = WriteTempFile({}, outputFormat);
                try {
                    TrimAudio(tempInput, tempOutput, startMs, endMs);
                    auto outputBytes = ReadAndDeleteFile(tempOutput);
                    DeleteFileW(Utf8ToWide(tempInput).c_str());
                    shared_result->Success(flutter::EncodableValue(outputBytes));
                } catch (...) {
                    DeleteFileW(Utf8ToWide(tempInput).c_str());
                    DeleteFileW(Utf8ToWide(tempOutput).c_str());
                    throw;
                }
            } catch (const std::exception& e) {
                shared_result->Error("TRIM_ERROR", e.what());
            }
        }).detach();

    } else if (method_call.method_name() == "getWaveformBytes") {
        if (!args) {
            result->Error("INVALID_ARGUMENTS", "Arguments map is required");
            return;
        }
        auto dataIt = args->find(flutter::EncodableValue("inputData"));
        auto hintIt = args->find(flutter::EncodableValue("formatHint"));
        auto samplesIt = args->find(flutter::EncodableValue("numberOfSamples"));
        if (dataIt == args->end() || hintIt == args->end() || samplesIt == args->end()) {
            result->Error("INVALID_ARGUMENTS", "inputData, formatHint and numberOfSamples are required");
            return;
        }
        auto inputData = std::get<std::vector<uint8_t>>(dataIt->second);
        std::string formatHint = std::get<std::string>(hintIt->second);
        int numberOfSamples = std::get<int32_t>(samplesIt->second);
        std::string normalization = "perFile";
        auto normIt = args->find(flutter::EncodableValue("normalization"));
        if (normIt != args->end()) {
            if (auto* s = std::get_if<std::string>(&normIt->second)) {
                normalization = *s;
            }
        }

        auto shared_result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
            std::move(result));
        std::thread([this, inputData = std::move(inputData), formatHint, numberOfSamples, normalization, shared_result]() {
            try {
                std::string tempInput = WriteTempFile(inputData, formatHint);
                try {
                    auto waveform = GetWaveform(tempInput, numberOfSamples, normalization);
                    DeleteFileW(Utf8ToWide(tempInput).c_str());
                    shared_result->Success(flutter::EncodableValue(waveform));
                } catch (...) {
                    DeleteFileW(Utf8ToWide(tempInput).c_str());
                    throw;
                }
            } catch (const std::exception& e) {
                shared_result->Error("WAVEFORM_ERROR", e.what());
            }
        }).detach();

    } else {
        result->NotImplemented();
    }
}

AudioDecoderPlugin::PcmInfo AudioDecoderPlugin::DecodeToPcmStream(
    const std::string& inputPath,
    const std::function<void(const uint8_t*, size_t)>& onChunk,
    int64_t startMs, int64_t endMs,
    int targetSampleRate, int targetChannels, int targetBitDepth,
    const std::function<void(const PcmInfo&)>& onFormat) {

    MFSession session;
    if (!session.IsInitialized()) {
        throw std::runtime_error("Failed to initialize Media Foundation");
    }

    std::wstring wInputPath = Utf8ToWide(inputPath);

    IMFSourceReader* pReader = nullptr;
    HRESULT hr = MFCreateSourceReaderFromURL(wInputPath.c_str(), nullptr, &pReader);
    if (FAILED(hr)) {
        throw std::runtime_error("Failed to create source reader for input file");
    }

    int bitsPerSampleHint = (targetBitDepth > 0) ? targetBitDepth : 16;

    IMFMediaType* pPartialType = nullptr;
    MFCreateMediaType(&pPartialType);
    pPartialType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    pPartialType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
    pPartialType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, bitsPerSampleHint);
    if (targetSampleRate > 0) {
        pPartialType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, targetSampleRate);
    }
    if (targetChannels > 0) {
        pPartialType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, targetChannels);
    }

    hr = pReader->SetCurrentMediaType(
        (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM,
        nullptr, pPartialType);
    pPartialType->Release();

    if (FAILED(hr)) {
        pReader->Release();
        throw std::runtime_error("Failed to set output media type to PCM");
    }

    if (startMs >= 0) {
        PROPVARIANT var;
        PropVariantInit(&var);
        var.vt = VT_I8;
        var.hVal.QuadPart = startMs * kHnsPerMs;
        pReader->SetCurrentPosition(GUID_NULL, var);
        PropVariantClear(&var);
    }

    IMFMediaType* pOutputType = nullptr;
    hr = pReader->GetCurrentMediaType(
        (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, &pOutputType);
    if (FAILED(hr)) {
        pReader->Release();
        throw std::runtime_error("Failed to get current media type");
    }

    UINT32 sampleRate = 0, channels = 0, bitsPerSample = 0;
    pOutputType->GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, &sampleRate);
    pOutputType->GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, &channels);
    pOutputType->GetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, &bitsPerSample);
    pOutputType->Release();

    PcmInfo info{};
    info.sampleRate = sampleRate;
    info.channels = channels;
    info.bitsPerSample = bitsPerSample;

    if (onFormat) {
        try {
            onFormat(info);
        } catch (...) {
            pReader->Release();
            throw;
        }
    }

    // WMF ignores the AAC edit list, causing timestamps to overshoot chunk
    // boundaries. Instead, compute exact byte limits from the duration.
    const int64_t blockAlign = channels * (bitsPerSample / 8);
    const int64_t bytesPerSec = sampleRate * blockAlign;

    // A malformed media type (channels, bitsPerSample or sampleRate reported as
    // 0) leaves us without a usable byte rate. Without it we cannot compute byte
    // windows, so fall back to passing samples through unbounded rather than
    // dividing by zero or silently emitting nothing (maxBytes would be 0).
    const bool canWindow = blockAlign > 0 && sampleRate > 0;

    // Treat an unspecified start (startMs < 0) as 0 so an explicit endMs still
    // bounds the output; decoding already begins at 0 when no seek was issued.
    const int64_t windowStartMs = (startMs > 0) ? startMs : 0;

    // A specified endMs always bounds the output: an empty or reversed window
    // (endMs <= windowStartMs) clamps to 0 bytes, matching the empty-trim
    // behaviour of the other platforms. Only an unspecified endMs (< 0) decodes
    // to the end of the stream.
    const int64_t maxBytes = (canWindow && endMs >= 0)
        ? (std::max)(int64_t{0}, endMs - windowStartMs) * bytesPerSec / 1000 / blockAlign * blockAlign
        : -1;
    int64_t bytesWritten = 0;
    int64_t startSkipBytes = (canWindow && startMs > 0) ? -1 : 0;

    try {
        while (true) {
            DWORD flags = 0;
            LONGLONG timestamp = 0;
            IMFSample* pSample = nullptr;
            hr = pReader->ReadSample(
                (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM,
                0, nullptr, &flags, &timestamp, &pSample);

            if (FAILED(hr)) break;
            if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
                if (pSample) pSample->Release();
                break;
            }

            if (maxBytes >= 0 && bytesWritten >= maxBytes) {
                if (pSample) pSample->Release();
                break;
            }

            if (pSample) {
                if (startSkipBytes < 0) {
                    const int64_t diffHns = startMs * kHnsPerMs - timestamp;
                    startSkipBytes = (diffHns > 0)
                        ? diffHns * bytesPerSec / kHnsPerSec / blockAlign * blockAlign
                        : 0;
                }

                IMFMediaBuffer* pBuffer = nullptr;
                pSample->ConvertToContiguousBuffer(&pBuffer);
                if (pBuffer) {
                    BYTE* pAudioData = nullptr;
                    DWORD cbBuffer = 0;
                    hr = pBuffer->Lock(&pAudioData, nullptr, &cbBuffer);
                    if (SUCCEEDED(hr)) {
                        DWORD offset = 0;
                        if (startSkipBytes > 0) {
                            if ((int64_t)cbBuffer <= startSkipBytes) {
                                startSkipBytes -= cbBuffer;
                                offset = cbBuffer;
                            } else {
                                offset = (DWORD)startSkipBytes;
                                startSkipBytes = 0;
                            }
                        }

                        if (offset < cbBuffer) {
                            DWORD toWrite = cbBuffer - offset;
                            if (maxBytes >= 0) {
                                int64_t remaining = maxBytes - bytesWritten;
                                if ((int64_t)toWrite > remaining) {
                                    toWrite = (DWORD)(remaining / blockAlign * blockAlign);
                                }
                            }
                            try {
                                onChunk(pAudioData + offset, toWrite);
                                bytesWritten += toWrite;
                            } catch (...) {
                                pBuffer->Unlock();
                                pBuffer->Release();
                                pSample->Release();
                                throw;
                            }
                        }
                        pBuffer->Unlock();
                    }
                    pBuffer->Release();
                }
                pSample->Release();
            }
        }
    } catch (...) {
        pReader->Release();
        throw;
    }
    pReader->Release();

    return info;
}

AudioDecoderPlugin::PcmInfo AudioDecoderPlugin::StreamPcmToWav(
    const std::string& inputPath, const std::string& outputPath,
    int64_t startMs, int64_t endMs,
    int targetSampleRate, int targetChannels, int targetBitDepth) {

    std::wstring wOutputPath = Utf8ToWide(outputPath);
    std::fstream file(wOutputPath,
                      std::ios::binary | std::ios::in | std::ios::out | std::ios::trunc);
    if (!file.is_open()) {
        throw std::runtime_error("Cannot open output file for writing");
    }

    WriteWavHeader(file, 0, 0, 0, 0);

    int64_t totalPcmBytes = 0;
    PcmInfo info{};
    try {
        info = DecodeToPcmStream(inputPath,
            [&](const uint8_t* data, size_t size) {
                file.write(reinterpret_cast<const char*>(data), size);
                if (!file) {
                    throw std::runtime_error("Failed to write PCM data to WAV file");
                }
                totalPcmBytes += static_cast<int64_t>(size);
                if (totalPcmBytes > kMaxWavDataSize) {
                    throw std::runtime_error("WAV output exceeds maximum size (~4 GB)");
                }
            },
            startMs, endMs, targetSampleRate, targetChannels, targetBitDepth);
    } catch (...) {
        file.close();
        DeleteFileW(wOutputPath.c_str());
        throw;
    }

    if (totalPcmBytes == 0) {
        file.close();
        DeleteFileW(wOutputPath.c_str());
        throw std::runtime_error("No audio data decoded");
    }

    file.seekp(0);
    if (!file) {
        file.close();
        DeleteFileW(wOutputPath.c_str());
        throw std::runtime_error("Failed to seek to beginning of WAV file");
    }
    WriteWavHeader(file, static_cast<uint32_t>(totalPcmBytes), info.sampleRate,
                   static_cast<uint16_t>(info.channels),
                   static_cast<uint16_t>(info.bitsPerSample));
    file.close();
    return info;
}

std::string AudioDecoderPlugin::ConvertToWav(
    const std::string& inputPath, const std::string& outputPath,
    int targetSampleRate, int targetChannels, int targetBitDepth) {

    StreamPcmToWav(inputPath, outputPath, -1, -1,
                   targetSampleRate, targetChannels, targetBitDepth);
    return outputPath;
}

std::string AudioDecoderPlugin::ConvertToM4a(
    const std::string& inputPath, const std::string& outputPath) {

    MFSession session;
    if (!session.IsInitialized()) {
        throw std::runtime_error("Failed to initialize Media Foundation");
    }

    std::wstring wInputPath = Utf8ToWide(inputPath);
    std::wstring wOutputPath = Utf8ToWide(outputPath);

    DeleteFileW(wOutputPath.c_str());

    IMFSourceReader* pReader = nullptr;
    HRESULT hr = MFCreateSourceReaderFromURL(wInputPath.c_str(), nullptr, &pReader);
    if (FAILED(hr)) {
        throw std::runtime_error("Failed to create source reader for input file");
    }

    IMFMediaType* pPcmType = nullptr;
    MFCreateMediaType(&pPcmType);
    pPcmType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    pPcmType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
    pPcmType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);

    hr = pReader->SetCurrentMediaType(
        (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, nullptr, pPcmType);
    pPcmType->Release();

    if (FAILED(hr)) {
        pReader->Release();
        throw std::runtime_error("Failed to set PCM output type on source reader");
    }

    IMFMediaType* pReaderOutputType = nullptr;
    pReader->GetCurrentMediaType(
        (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, &pReaderOutputType);

    UINT32 sampleRate = 0, channels = 0;
    pReaderOutputType->GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, &sampleRate);
    pReaderOutputType->GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, &channels);
    pReaderOutputType->Release();

    IMFSinkWriter* pWriter = nullptr;
    hr = MFCreateSinkWriterFromURL(wOutputPath.c_str(), nullptr, nullptr, &pWriter);
    if (FAILED(hr)) {
        pReader->Release();
        throw std::runtime_error("Failed to create sink writer for output file");
    }

    IMFMediaType* pAacType = nullptr;
    MFCreateMediaType(&pAacType);
    pAacType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    pAacType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
    pAacType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, sampleRate);
    pAacType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, channels);
    pAacType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
    pAacType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 128000 / 8);

    DWORD writerStreamIndex = 0;
    hr = pWriter->AddStream(pAacType, &writerStreamIndex);
    pAacType->Release();

    if (FAILED(hr)) {
        pWriter->Release();
        pReader->Release();
        throw std::runtime_error("Failed to add AAC stream to sink writer");
    }

    IMFMediaType* pInputType = nullptr;
    MFCreateMediaType(&pInputType);
    pInputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    pInputType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
    pInputType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, sampleRate);
    pInputType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, channels);
    pInputType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
    pInputType->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, channels * 2);
    pInputType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, sampleRate * channels * 2);

    hr = pWriter->SetInputMediaType(writerStreamIndex, pInputType, nullptr);
    pInputType->Release();

    if (FAILED(hr)) {
        pWriter->Release();
        pReader->Release();
        throw std::runtime_error("Failed to set input media type on sink writer");
    }

    hr = pWriter->BeginWriting();
    if (FAILED(hr)) {
        pWriter->Release();
        pReader->Release();
        throw std::runtime_error("Failed to begin writing");
    }

    while (true) {
        DWORD flags = 0;
        IMFSample* pSample = nullptr;
        hr = pReader->ReadSample(
            (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM,
            0, nullptr, &flags, nullptr, &pSample);

        if (FAILED(hr)) break;
        if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
            if (pSample) pSample->Release();
            break;
        }

        if (pSample) {
            hr = pWriter->WriteSample(writerStreamIndex, pSample);
            pSample->Release();
            if (FAILED(hr)) break;
        }
    }

    pWriter->Finalize();
    pWriter->Release();
    pReader->Release();

    return outputPath;
}

flutter::EncodableMap AudioDecoderPlugin::GetAudioInfo(const std::string& path) {
    MFSession session;
    if (!session.IsInitialized()) {
        throw std::runtime_error("Failed to initialize Media Foundation");
    }

    std::wstring wPath = Utf8ToWide(path);

    IMFSourceReader* pReader = nullptr;
    HRESULT hr = MFCreateSourceReaderFromURL(wPath.c_str(), nullptr, &pReader);
    if (FAILED(hr)) {
        throw std::runtime_error("Failed to create source reader for input file");
    }

    // Get duration from presentation descriptor
    PROPVARIANT varDuration;
    PropVariantInit(&varDuration);
    int64_t durationMs = 0;

    IMFMediaSource* pSource = nullptr;
    hr = pReader->GetServiceForStream(
        static_cast<DWORD>(MF_SOURCE_READER_MEDIASOURCE), GUID_NULL,
        __uuidof(IMFMediaSource), reinterpret_cast<LPVOID*>(&pSource));
    if (SUCCEEDED(hr) && pSource) {
        IMFPresentationDescriptor* pPD = nullptr;
        hr = pSource->CreatePresentationDescriptor(&pPD);
        if (SUCCEEDED(hr) && pPD) {
            hr = pPD->GetItem(MF_PD_DURATION, &varDuration);
            if (SUCCEEDED(hr) && varDuration.vt == VT_UI8) {
                durationMs = static_cast<int64_t>(varDuration.uhVal.QuadPart / 10000);
            }
            pPD->Release();
        }
        pSource->Release();
    }
    PropVariantClear(&varDuration);

    // Get audio format info
    IMFMediaType* pNativeType = nullptr;
    hr = pReader->GetNativeMediaType(
        (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, 0, &pNativeType);

    UINT32 sampleRate = 0, channels = 0, bitRate = 0;
    std::string format = "unknown";

    if (SUCCEEDED(hr) && pNativeType) {
        pNativeType->GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, &sampleRate);
        pNativeType->GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, &channels);
        pNativeType->GetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, &bitRate);
        bitRate *= 8;

        GUID subtype;
        if (SUCCEEDED(pNativeType->GetGUID(MF_MT_SUBTYPE, &subtype))) {
            if (subtype == MFAudioFormat_PCM) format = "pcm";
            else if (subtype == MFAudioFormat_MP3) format = "mp3";
            else if (subtype == MFAudioFormat_AAC) format = "aac";
            else if (subtype == MFAudioFormat_FLAC) format = "flac";
            else if (subtype == MFAudioFormat_WMAudioV8 ||
                     subtype == MFAudioFormat_WMAudioV9 ||
                     subtype == MFAudioFormat_WMAudio_Lossless) format = "wma";
            else if (subtype == MFAudioFormat_ALAC) format = "alac";
            else if (subtype == MFAudioFormat_Opus) format = "opus";
            else format = "unknown";
        }
        pNativeType->Release();
    }

    pReader->Release();

    flutter::EncodableMap info;
    info[flutter::EncodableValue("durationMs")] = flutter::EncodableValue(static_cast<int32_t>(durationMs));
    info[flutter::EncodableValue("sampleRate")] = flutter::EncodableValue(static_cast<int32_t>(sampleRate));
    info[flutter::EncodableValue("channels")] = flutter::EncodableValue(static_cast<int32_t>(channels));
    info[flutter::EncodableValue("bitRate")] = flutter::EncodableValue(static_cast<int32_t>(bitRate));
    info[flutter::EncodableValue("format")] = flutter::EncodableValue(format);
    return info;
}

std::string AudioDecoderPlugin::TrimAudio(
    const std::string& inputPath, const std::string& outputPath,
    int64_t startMs, int64_t endMs) {

    std::string ext = outputPath.substr(outputPath.find_last_of('.') + 1);
    std::transform(ext.begin(), ext.end(), ext.begin(),
                   [](unsigned char c) {
                       return static_cast<char>(std::tolower(c));
                   });

    if (ext == "m4a") {
        // The trimmed PCM is fed to the sink writer chunk by chunk while the
        // source reader is still decoding, so trimming hours of audio costs no
        // more memory than trimming seconds (#49).
        MFSession session;
        if (!session.IsInitialized()) {
            throw std::runtime_error("Failed to initialize Media Foundation");
        }

        M4aStreamWriter writer(outputPath);
        int64_t bytesWritten = 0;
        try {
            DecodeToPcmStream(inputPath,
                [&](const uint8_t* data, size_t size) {
                    writer.WriteChunk(data, size);
                    bytesWritten += static_cast<int64_t>(size);
                },
                startMs, endMs, -1, -1, -1,
                [&](const PcmInfo& info) {
                    writer.Begin(info.sampleRate, info.channels);
                });
        } catch (...) {
            writer.Abort();
            throw;
        }

        if (bytesWritten == 0) {
            writer.Abort();
            throw std::runtime_error("No audio data decoded from trim range");
        }

        writer.Finish();
    } else {
        StreamPcmToWav(inputPath, outputPath, startMs, endMs);
    }

    return outputPath;
}

flutter::EncodableList AudioDecoderPlugin::GetWaveform(
    const std::string& path, int numberOfSamples,
    const std::string& normalization) {

    // Fail fast on an invalid normalization mode before doing the expensive
    // decode + RMS work below.
    if (normalization != "perFile" && normalization != "absolute") {
        throw std::invalid_argument(
            "Unknown waveform normalization: " + normalization);
    }

    // RMS energy is folded into the accumulator while decoding, so the whole
    // track never has to be held in memory (#49).
    WaveformAccumulator accumulator(numberOfSamples);
    DecodeToPcmStream(path, [&](const uint8_t* data, size_t size) {
        accumulator.AddPcm(data, size);
    });

    flutter::EncodableList result;
    for (double value : accumulator.Build(normalization)) {
        result.push_back(flutter::EncodableValue(value));
    }
    return result;
}

void AudioDecoderPlugin::WriteWavHeader(
    std::ostream& file, uint32_t dataSize, uint32_t sampleRate,
    uint16_t channels, uint16_t bitsPerSample) {

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

std::string AudioDecoderPlugin::WriteTempFile(
    const std::vector<uint8_t>& data, const std::string& extension) {
    wchar_t tempPath[MAX_PATH];
    GetTempPathW(MAX_PATH, tempPath);

    wchar_t tempFile[MAX_PATH];
    GetTempFileNameW(tempPath, L"aud", 0, tempFile);

    // Rename with proper extension
    std::wstring wTempFile(tempFile);
    std::wstring wNewPath = wTempFile + L"." + Utf8ToWide(extension);
    MoveFileW(tempFile, wNewPath.c_str());

    // Write data if non-empty
    if (!data.empty()) {
        std::ofstream file(wNewPath, std::ios::binary);
        file.write(reinterpret_cast<const char*>(data.data()), data.size());
        file.close();
    }

    return WideToUtf8(wNewPath);
}

std::vector<uint8_t> AudioDecoderPlugin::ReadAndDeleteFile(const std::string& path) {
    std::wstring wPath = Utf8ToWide(path);
    std::ifstream file(wPath, std::ios::binary | std::ios::ate);
    if (!file.is_open()) {
        throw std::runtime_error("Cannot read output file");
    }
    auto size = file.tellg();
    file.seekg(0, std::ios::beg);
    std::vector<uint8_t> bytes(size);
    file.read(reinterpret_cast<char*>(bytes.data()), size);
    file.close();
    DeleteFileW(wPath.c_str());
    return bytes;
}

}  // namespace audio_decoder
