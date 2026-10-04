//
//  MediaCapabilities.swift
//  Hayase
//
//  Mirrors: the media tests of src/routes/app/debug/+page.svelte: the codecs, sample rates, channel counts and
//  resolutions that it tests (`AUDIO_CODECS`, `SAMPLE_RATES`, `CHANNELS`, `VIDEO_CODECS`, `RESOLUTIONS`), and
//  `testAudio`, `testVideo` and the formats of `media()`.
//
//  The interface asks the web decoders (`AudioDecoder.isConfigSupported`, `VideoDecoder.isConfigSupported`,
//  `canPlayType`). Those are the decoders of the system, so here it is the system's: AudioToolbox for what an audio
//  converter can be made for, VideoToolbox for the video decoders that the device has, and AVFoundation for what a
//  codec string can play. iOS has no way to ask a video decoder about a size, so a resolution is supported when
//  the codec is and it is not past 4K, which is what its hardware decoders do.
//

import AudioToolbox
import AVFoundation
import VideoToolbox

enum MediaCapabilities {
    static let audioCodecs: [(codec: String, name: String)] = [
        ("opus", "Opus"),
        ("mp4a.40.2", "AAC LC"),
        ("mp3", "MP3"),
        ("vorbis", "Vorbis"),
        ("flac", "FLAC"),
        ("alac", "ALAC"),
        ("ac-3", "AC-3"),
        ("dtsc", "DTS Core"),
        ("truehd", "TrueHD"),
    ]

    static let sampleRates = [8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000, 88200, 96000]
    static let channels = [8, 6, 4, 2, 1]

    static let videoCodecs: [(codec: String, name: String)] = [
        ("avc1.420033", "H.264 Baseline"),
        ("avc1.4D0033", "H.264 Main"),
        ("avc1.640033", "H.264 High"),
        ("avc1.6E0033", "H.264 High 10"),
        ("avc1.7A0033", "H.264 High 4:2:2"),
        ("avc1.F40033", "H.264 High 4:4:4"),
        ("hev1.1.6.L93.B0", "H.265 Main"),
        ("hev1.2.4.L93.B0", "H.265 Main 10"),
        ("hev1.4.4.L93.B0", "H.265 Main 4:2:2"),
        ("hev1.6.4.L93.B0", "H.265 Main 4:4:4"),
        ("av01.0.05M.08", "AV1 P0"),
        ("av01.1.05M.08", "AV1 P1"),
        ("av01.2.05M.10", "AV1 P2 10-bit"),
        ("vp09.00.10.08", "VP9 P0"),
        ("vp09.02.10.08", "VP9 P2"),
        ("vp8", "VP8"),
    ]

    static let resolutions: [(width: Int, height: Int, label: String)] = [
        (426, 240, "240p"),
        (640, 360, "360p"),
        (854, 480, "SD"),
        (1280, 720, "HD"),
        (1920, 1080, "FHD"),
        (2560, 1440, "2K"),
        (3840, 2160, "4K"),
        (7680, 4320, "8K"),
    ]

    // MARK: - testAudio

    /// `testAudio`: for each codec and sample rate the most channels that it can decode, 0 when none
    static func testAudio() -> [String: [Int: Int]] {
        var result: [String: [Int: Int]] = [:]
        for (codec, _) in audioCodecs {
            var rates: [Int: Int] = [:]
            for sampleRate in sampleRates {
                rates[sampleRate] = channels.first { decodes(codec: codec, sampleRate: sampleRate, channels: $0) } ?? 0
            }
            result[codec] = rates
        }
        return result
    }

    /// `AudioDecoder.isConfigSupported({ codec, sampleRate, numberOfChannels })`: whether the system makes an audio converter
    /// from the codec to PCM at that rate and channel count
    private static func decodes(codec: String, sampleRate: Int, channels: Int) -> Bool {
        let format: (id: AudioFormatID, flags: UInt32, framesPerPacket: UInt32)
        switch codec {
        case "opus": format = (kAudioFormatOpus, 0, 960)
        case "mp4a.40.2": format = (kAudioFormatMPEG4AAC, UInt32(MPEG4ObjectID.AAC_LC.rawValue), 1024)
        case "mp3": format = (kAudioFormatMPEGLayer3, 0, 1152)
        case "flac": format = (kAudioFormatFLAC, 0, 4096)
        case "alac": format = (kAudioFormatAppleLossless, 0, 4096)
        case "ac-3": format = (kAudioFormatAC3, 0, 1536)
        default: return false   // Vorbis, DTS and TrueHD have no decoder in the system
        }
        var input = AudioStreamBasicDescription(mSampleRate: Float64(sampleRate), mFormatID: format.id,
                                                mFormatFlags: format.flags, mBytesPerPacket: 0,
                                                mFramesPerPacket: format.framesPerPacket, mBytesPerFrame: 0,
                                                mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 0, mReserved: 0)
        var output = AudioStreamBasicDescription(mSampleRate: Float64(sampleRate), mFormatID: kAudioFormatLinearPCM,
                                                 mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                                 mBytesPerPacket: UInt32(4 * channels), mFramesPerPacket: 1,
                                                 mBytesPerFrame: UInt32(4 * channels), mChannelsPerFrame: UInt32(channels),
                                                 mBitsPerChannel: 32, mReserved: 0)
        var converter: AudioConverterRef?
        let status = AudioConverterNew(&input, &output, &converter)
        if let converter { AudioConverterDispose(converter) }
        return status == noErr
    }

    // MARK: - testVideo

    /// `testVideo`: for each codec and resolution whether it can be decoded
    static func testVideo() -> [String: [String: Bool]] {
        var result: [String: [String: Bool]] = [:]
        for (codec, _) in videoCodecs {
            let supported = decodesVideo(codec: codec)
            var sizes: [String: Bool] = [:]
            for resolution in resolutions {
                // `VideoDecoder.isConfigSupported({ codec, codedWidth, codedHeight })`
                sizes[resolution.label] = supported && resolution.width <= 3840
            }
            result[codec] = sizes
        }
        return result
    }

    /// Whether the system has a decoder for the codec: it plays the codec string, or the video decoders have it
    private static func decodesVideo(codec: String) -> Bool {
        if AVURLAsset.isPlayableExtendedMIMEType("video/mp4; codecs=\"\(codec)\"") { return true }
        let type: CMVideoCodecType
        switch codec.prefix(4) {
        case "avc1": type = 0x61766331   // 'avc1'
        case "hev1": type = 0x68766331   // 'hvc1'
        case "av01": type = 0x61763031   // 'av01'
        case "vp09": type = 0x76703039   // 'vp09'
        default: return false
        }
        return VTIsHardwareDecodeSupported(type)
    }

    // MARK: - media

    /// The `video` list of `media()`: the formats of the codecs that can be played, as `canPlayType` says
    static func playableFormats() -> [String] {
        var formats: [String] = []
        for (codec, _) in videoCodecs {
            let format = "video/mp4; codecs=\"\(codec)\""
            if AVURLAsset.isPlayableExtendedMIMEType(format) { formats.append(format) }
        }
        for (codec, _) in audioCodecs {
            let format = "audio/mp4; codecs=\"\(codec)\""
            if AVURLAsset.isPlayableExtendedMIMEType(format) { formats.append(format) }
        }
        // `'audioTracks' in HTMLVideoElement.prototype`: a video here has its audio tracks
        formats.append("audioTracks")
        return formats
    }
}
