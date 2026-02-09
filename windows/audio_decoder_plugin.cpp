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

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "mf.lib")

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

        auto shared_result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
            std::move(result));
        std::thread([this, inputPath, outputPath, shared_result]() {
            try {
                std::string output = ConvertToWav(inputPath, outputPath);
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

        auto shared_result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
            std::move(result));
        std::thread([this, path, numberOfSamples, shared_result]() {
            try {
                auto waveform = GetWaveform(path, numberOfSamples);
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

        auto shared_result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
            std::move(result));
        std::thread([this, inputData = std::move(inputData), formatHint, shared_result]() {
            try {
                std::string tempInput = WriteTempFile(inputData, formatHint);
                std::string tempOutput = WriteTempFile({}, "wav");
                try {
                    ConvertToWav(tempInput, tempOutput);
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

        auto shared_result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
            std::move(result));
        std::thread([this, inputData = std::move(inputData), formatHint, numberOfSamples, shared_result]() {
            try {
                std::string tempInput = WriteTempFile(inputData, formatHint);
                try {
                    auto waveform = GetWaveform(tempInput, numberOfSamples);
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

AudioDecoderPlugin::PcmResult AudioDecoderPlugin::DecodeToPcm(
    const std::string& inputPath, int64_t startMs, int64_t endMs) {

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

    IMFMediaType* pPartialType = nullptr;
    MFCreateMediaType(&pPartialType);
    pPartialType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    pPartialType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
    pPartialType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);

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
        var.hVal.QuadPart = startMs * 10000LL;
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

    int64_t endHns = (endMs >= 0) ? endMs * 10000LL : -1;

    std::vector<uint8_t> pcmData;
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

        if (endHns >= 0 && timestamp > endHns) {
            if (pSample) pSample->Release();
            break;
        }

        if (pSample) {
            IMFMediaBuffer* pBuffer = nullptr;
            pSample->ConvertToContiguousBuffer(&pBuffer);
            if (pBuffer) {
                BYTE* pAudioData = nullptr;
                DWORD cbBuffer = 0;
                hr = pBuffer->Lock(&pAudioData, nullptr, &cbBuffer);
                if (SUCCEEDED(hr)) {
                    pcmData.insert(pcmData.end(), pAudioData, pAudioData + cbBuffer);
                    pBuffer->Unlock();
                }
                pBuffer->Release();
            }
            pSample->Release();
        }
    }
    pReader->Release();

    PcmResult res;
    res.data = std::move(pcmData);
    res.sampleRate = sampleRate;
    res.channels = channels;
    res.bitsPerSample = bitsPerSample;
    return res;
}

std::string AudioDecoderPlugin::ConvertToWav(
    const std::string& inputPath, const std::string& outputPath) {

    auto pcm = DecodeToPcm(inputPath);

    if (pcm.data.empty()) {
        throw std::runtime_error("No audio data decoded from input file");
    }

    std::wstring wOutputPath = Utf8ToWide(outputPath);
    std::ofstream file(wOutputPath, std::ios::binary);
    if (!file.is_open()) {
        throw std::runtime_error("Cannot open output file for writing");
    }

    WriteWavHeader(file, static_cast<uint32_t>(pcm.data.size()), pcm.sampleRate,
                   static_cast<uint16_t>(pcm.channels), static_cast<uint16_t>(pcm.bitsPerSample));
    file.write(reinterpret_cast<char*>(pcm.data.data()), pcm.data.size());
    file.close();

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
        MF_SOURCE_READER_MEDIASOURCE, GUID_NULL,
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

    auto pcm = DecodeToPcm(inputPath, startMs, endMs);

    if (pcm.data.empty()) {
        throw std::runtime_error("No audio data decoded from trim range");
    }

    std::string ext = outputPath.substr(outputPath.find_last_of('.') + 1);
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);

    if (ext == "m4a") {
        MFSession session;
        if (!session.IsInitialized()) {
            throw std::runtime_error("Failed to initialize Media Foundation");
        }

        std::wstring wOutputPath = Utf8ToWide(outputPath);
        DeleteFileW(wOutputPath.c_str());

        IMFSinkWriter* pWriter = nullptr;
        HRESULT hr = MFCreateSinkWriterFromURL(wOutputPath.c_str(), nullptr, nullptr, &pWriter);
        if (FAILED(hr)) {
            throw std::runtime_error("Failed to create sink writer");
        }

        IMFMediaType* pAacType = nullptr;
        MFCreateMediaType(&pAacType);
        pAacType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
        pAacType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
        pAacType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, pcm.sampleRate);
        pAacType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, pcm.channels);
        pAacType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
        pAacType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 128000 / 8);

        DWORD streamIndex = 0;
        hr = pWriter->AddStream(pAacType, &streamIndex);
        pAacType->Release();
        if (FAILED(hr)) { pWriter->Release(); throw std::runtime_error("Failed to add AAC stream"); }

        IMFMediaType* pInputType = nullptr;
        MFCreateMediaType(&pInputType);
        pInputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
        pInputType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
        pInputType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, pcm.sampleRate);
        pInputType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, pcm.channels);
        pInputType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
        pInputType->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, pcm.channels * 2);
        pInputType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, pcm.sampleRate * pcm.channels * 2);

        hr = pWriter->SetInputMediaType(streamIndex, pInputType, nullptr);
        pInputType->Release();
        if (FAILED(hr)) { pWriter->Release(); throw std::runtime_error("Failed to set input type"); }

        hr = pWriter->BeginWriting();
        if (FAILED(hr)) { pWriter->Release(); throw std::runtime_error("Failed to begin writing"); }

        DWORD blockAlign = pcm.channels * 2;
        DWORD chunkSize = pcm.sampleRate * blockAlign;
        LONGLONG timestamp = 0;

        for (size_t offset = 0; offset < pcm.data.size(); offset += chunkSize) {
            DWORD thisChunk = static_cast<DWORD>(
                std::min(static_cast<size_t>(chunkSize), pcm.data.size() - offset));

            IMFMediaBuffer* pBuffer = nullptr;
            MFCreateMemoryBuffer(thisChunk, &pBuffer);
            BYTE* pBufData = nullptr;
            pBuffer->Lock(&pBufData, nullptr, nullptr);
            memcpy(pBufData, pcm.data.data() + offset, thisChunk);
            pBuffer->Unlock();
            pBuffer->SetCurrentLength(thisChunk);

            IMFSample* pSample = nullptr;
            MFCreateSample(&pSample);
            pSample->AddBuffer(pBuffer);
            pSample->SetSampleTime(timestamp);
            LONGLONG duration = (LONGLONG)thisChunk * 10000000LL / (pcm.sampleRate * blockAlign);
            pSample->SetSampleDuration(duration);

            pWriter->WriteSample(streamIndex, pSample);
            timestamp += duration;

            pSample->Release();
            pBuffer->Release();
        }

        pWriter->Finalize();
        pWriter->Release();
    } else {
        std::wstring wOutputPath = Utf8ToWide(outputPath);
        std::ofstream file(wOutputPath, std::ios::binary);
        if (!file.is_open()) {
            throw std::runtime_error("Cannot open output file for writing");
        }
        WriteWavHeader(file, static_cast<uint32_t>(pcm.data.size()), pcm.sampleRate,
                       static_cast<uint16_t>(pcm.channels), static_cast<uint16_t>(pcm.bitsPerSample));
        file.write(reinterpret_cast<char*>(pcm.data.data()), pcm.data.size());
        file.close();
    }

    return outputPath;
}

flutter::EncodableList AudioDecoderPlugin::GetWaveform(
    const std::string& path, int numberOfSamples) {

    auto pcm = DecodeToPcm(path);

    if (pcm.data.empty()) {
        flutter::EncodableList result;
        for (int i = 0; i < numberOfSamples; i++) {
            result.push_back(flutter::EncodableValue(0.0));
        }
        return result;
    }

    const int16_t* samples = reinterpret_cast<const int16_t*>(pcm.data.data());
    size_t totalSamples = pcm.data.size() / 2;
    size_t samplesPerWindow = std::max(static_cast<size_t>(1), totalSamples / numberOfSamples);

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

    flutter::EncodableList result;
    for (size_t i = 0; i < waveform.size(); i++) {
        double normalized = (maxRms > 0) ? waveform[i] / maxRms : 0.0;
        result.push_back(flutter::EncodableValue(normalized));
    }

    while (static_cast<int>(result.size()) < numberOfSamples) {
        result.push_back(flutter::EncodableValue(0.0));
    }

    return result;
}

void AudioDecoderPlugin::WriteWavHeader(
    std::ofstream& file, uint32_t dataSize, uint32_t sampleRate,
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
