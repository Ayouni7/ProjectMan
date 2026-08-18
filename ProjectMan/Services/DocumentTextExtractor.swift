import Foundation
import zlib

enum DocumentTextExtractor {
    static func extractText(from url: URL) throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        if ext == "docx" {
            return try extractDocx(url)
        }
        if ext == "txt" || ext == "md" {
            return try String(contentsOf: url, encoding: .utf8)
        }
        return ""
    }

    private static func extractDocx(_ url: URL) throws -> String {
        let zip = try Data(contentsOf: url)
        let xmlData = try MiniZip.data(named: "word/document.xml", from: zip)
        guard let xml = String(data: xmlData, encoding: .utf8) else {
            throw DocumentError.unreadable
        }
        return stripXML(xml)
    }

    private static func stripXML(_ xml: String) -> String {
        var text = xml.replacingOccurrences(of: "</w:p>", with: "\n")
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        return text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum DocumentError: LocalizedError {
    case unreadable
    var errorDescription: String? { "Could not read that document." }
}

enum FileKind {
    static func captureKind(for url: URL) -> CaptureKind {
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "docx": return .docx
        case "m4a", "wav", "mp3", "caf", "aac": return .audio
        default: return .photo
        }
    }

    static func isImage(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff"].contains(url.pathExtension.lowercased())
    }
}

private enum MiniZip {
    static func data(named: String, from zip: Data) throws -> Data {
        var offset = 0
        let bytes = [UInt8](zip)
        while offset + 30 <= bytes.count {
            guard bytes[offset] == 0x50, bytes[offset + 1] == 0x4B,
                  bytes[offset + 2] == 0x03, bytes[offset + 3] == 0x04 else {
                throw DocumentError.unreadable
            }
            let compression = u16(bytes, offset + 8)
            let compressedSize = Int(u32(bytes, offset + 18))
            let nameLen = Int(u16(bytes, offset + 26))
            let extraLen = Int(u16(bytes, offset + 28))
            let nameStart = offset + 30
            let nameEnd = nameStart + nameLen
            guard nameEnd <= bytes.count else { throw DocumentError.unreadable }
            let name = String(bytes: bytes[nameStart..<nameEnd], encoding: .utf8) ?? ""
            let dataStart = nameEnd + extraLen
            let dataEnd = dataStart + compressedSize
            guard dataEnd <= bytes.count else { throw DocumentError.unreadable }
            if name == named {
                let payload = Data(bytes[dataStart..<dataEnd])
                if compression == 0 { return payload }
                if compression == 8 { return try inflateRaw(payload) }
                throw DocumentError.unreadable
            }
            offset = dataEnd
        }
        throw DocumentError.unreadable
    }

    private static func u16(_ bytes: [UInt8], _ i: Int) -> UInt16 {
        UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8
    }

    private static func u32(_ bytes: [UInt8], _ i: Int) -> UInt32 {
        UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24
    }

    private static func inflateRaw(_ input: Data) throws -> Data {
        if input.isEmpty { return Data() }
        var packed = [UInt8](input)
        var stream = z_stream()
        var output = Data()
        var chunk = [UInt8](repeating: 0, count: 65_536)
        let chunkCount = chunk.count

        let status: Int32 = packed.withUnsafeMutableBufferPointer { inBuf in
            stream.next_in = inBuf.baseAddress
            stream.avail_in = uInt(inBuf.count)
            let initStatus = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            guard initStatus == Z_OK else { return initStatus }
            defer { inflateEnd(&stream) }

            var inflateStatus: Int32 = Z_OK
            repeat {
                inflateStatus = chunk.withUnsafeMutableBufferPointer { outBuf in
                    stream.next_out = outBuf.baseAddress
                    stream.avail_out = uInt(chunkCount)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let produced = chunkCount - Int(stream.avail_out)
                if produced > 0 {
                    output.append(contentsOf: chunk.prefix(produced))
                }
                if inflateStatus == Z_BUF_ERROR && stream.avail_in == 0 {
                    break
                }
            } while inflateStatus == Z_OK
            return inflateStatus
        }

        guard status == Z_STREAM_END || (status == Z_BUF_ERROR && !output.isEmpty) else {
            throw DocumentError.unreadable
        }
        return output
    }
}
