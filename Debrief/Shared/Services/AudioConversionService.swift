import Foundation

enum AudioConversionError: LocalizedError {
    case emptyPCM

    var errorDescription: String? {
        switch self {
        case .emptyPCM:
            return "PCM file was empty."
        }
    }
}

struct AudioConversionService {
    private static let streamBufferSize = 64 * 1024
    private let logger = PrintLogger.shared

    func convertPCMToWAV(inputURL: URL, outputURL: URL, sampleRate: Int = 16_000, channels: Int = 1) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: inputURL.path)
        let pcmSize = (attrs[.size] as? UInt64) ?? 0
        guard pcmSize > 0 else {
            logger.log("PCM file is empty — cannot convert: \(inputURL.path)")
            throw AudioConversionError.emptyPCM
        }

        logger.log("Converting PCM → WAV — input: \(inputURL.path), size: \(pcmSize / 1024) KB, sampleRate: \(sampleRate)Hz")
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let header = wavHeader(
            pcmDataSize: UInt32(pcmSize),
            sampleRate: UInt32(sampleRate),
            channels: UInt16(channels),
            bitsPerSample: 16
        )

        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle.close() }

        let inputHandle = try FileHandle(forReadingFrom: inputURL)
        defer { try? inputHandle.close() }

        try outputHandle.write(contentsOf: header)

        while true {
            let chunk: Data = autoreleasepool {
                inputHandle.readData(ofLength: Self.streamBufferSize)
            }
            if chunk.isEmpty { break }
            try outputHandle.write(contentsOf: chunk)
        }
        logger.log("PCM → WAV conversion complete — output: \(outputURL.path)")
    }

    private func wavHeader(
        pcmDataSize: UInt32,
        sampleRate: UInt32,
        channels: UInt16,
        bitsPerSample: UInt16
    ) -> Data {
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let chunkSize = 36 + pcmDataSize

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(contentsOf: chunkSize.littleEndianBytes)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(contentsOf: UInt32(16).littleEndianBytes)
        data.append(contentsOf: UInt16(1).littleEndianBytes)
        data.append(contentsOf: channels.littleEndianBytes)
        data.append(contentsOf: sampleRate.littleEndianBytes)
        data.append(contentsOf: byteRate.littleEndianBytes)
        data.append(contentsOf: blockAlign.littleEndianBytes)
        data.append(contentsOf: bitsPerSample.littleEndianBytes)
        data.append("data".data(using: .ascii)!)
        data.append(contentsOf: pcmDataSize.littleEndianBytes)
        return data
    }
}

private extension FixedWidthInteger {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian, Array.init)
    }
}
