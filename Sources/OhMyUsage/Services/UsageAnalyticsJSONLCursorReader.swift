import Foundation
import OhMyUsageApplication

/**
 * [INPUT]: 依赖 FileHandle 的 seek/chunk read 与 RuntimeDiagnosticsLimits 行长上限，接收已提交 byte offset。
 * [OUTPUT]: 对外提供只包含完整 UTF-8 行、下一安全提交 offset、读取字节和损坏诊断的 JSONL 批次。
 * [POS]: Services analytics ingest 的通用流式 reader；统一 Claude/Gemini/Qwen 后续增量 adapter 的边界处理。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

struct UsageAnalyticsJSONLCursorReader {
    enum ReadError: Error, Equatable {
        case offsetBeyondEnd(requested: UInt64, fileSize: UInt64)
    }

    private let chunkSize: Int
    private let maxLineBytes: Int

    init(
        chunkSize: Int = 64 * 1024,
        maxLineBytes: Int = RuntimeDiagnosticsLimits.jsonlMaxLineBytes
    ) {
        self.chunkSize = max(1, chunkSize)
        self.maxLineBytes = max(1, maxLineBytes)
    }

    func readCompleteLines(
        at url: URL,
        from committedOffset: UInt64
    ) throws -> UsageAnalyticsJSONLReadResult {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        guard committedOffset <= fileSize else {
            throw ReadError.offsetBeyondEnd(requested: committedOffset, fileSize: fileSize)
        }
        try handle.seek(toOffset: committedOffset)

        var lines: [String] = []
        var buffer = Data()
        var bufferStartOffset = committedOffset
        var bytesRead: UInt64 = 0
        var oversizedLineCount = 0
        var invalidUTF8LineCount = 0
        var droppingOversizedLine = false
        let newlineByte: UInt8 = 0x0A

        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            bytesRead += UInt64(chunk.count)
            var cursor = chunk.startIndex

            while cursor < chunk.endIndex {
                if droppingOversizedLine {
                    guard let newlineIndex = chunk[cursor...].firstIndex(of: newlineByte) else {
                        cursor = chunk.endIndex
                        continue
                    }
                    droppingOversizedLine = false
                    cursor = chunk.index(after: newlineIndex)
                    bufferStartOffset = committedOffset + bytesRead - UInt64(chunk.endIndex - cursor)
                    continue
                }

                guard let newlineIndex = chunk[cursor...].firstIndex(of: newlineByte) else {
                    buffer.append(contentsOf: chunk[cursor...])
                    cursor = chunk.endIndex
                    if buffer.count > maxLineBytes {
                        oversizedLineCount += 1
                        buffer.removeAll(keepingCapacity: false)
                        droppingOversizedLine = true
                    }
                    continue
                }

                buffer.append(contentsOf: chunk[cursor..<newlineIndex])
                let nextIndex = chunk.index(after: newlineIndex)
                let lineEndOffset = committedOffset + bytesRead - UInt64(chunk.endIndex - nextIndex)

                if !buffer.isEmpty {
                    if buffer.count <= maxLineBytes, let line = String(data: buffer, encoding: .utf8) {
                        lines.append(line)
                    } else if buffer.count <= maxLineBytes {
                        invalidUTF8LineCount += 1
                    } else {
                        oversizedLineCount += 1
                    }
                }

                buffer.removeAll(keepingCapacity: true)
                bufferStartOffset = lineEndOffset
                cursor = nextIndex
            }
        }

        let hasIncompleteTail = droppingOversizedLine || !buffer.isEmpty
        let safeOffset = hasIncompleteTail ? bufferStartOffset : committedOffset + bytesRead
        return UsageAnalyticsJSONLReadResult(
            lines: lines,
            committedOffset: safeOffset,
            bytesRead: bytesRead,
            oversizedLineCount: oversizedLineCount,
            invalidUTF8LineCount: invalidUTF8LineCount,
            hasIncompleteTail: hasIncompleteTail
        )
    }
}
