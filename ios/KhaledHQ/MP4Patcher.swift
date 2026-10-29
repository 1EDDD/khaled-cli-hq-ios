import Foundation

struct MP4PatchReport {
    let originalFrames: Int
    let declaredFrames: Int
    let insertedFrames: Int
    let outputBytes: Int64
}

enum MP4PatchError: LocalizedError {
    case malformed(String)
    case unsupported(String)
    case missing(String)
    case sizeLimit

    var errorDescription: String? {
        switch self {
        case .malformed(let message): return "ملف MP4 غير سليم: \(message)"
        case .unsupported(let message): return "نوع الفيديو غير مدعوم: \(message)"
        case .missing(let message): return "ما لقيت \(message) داخل MP4."
        case .sizeLimit: return "الملف أكبر من الحد الآمن لهذه النسخة."
        }
    }
}

/// A small ISO-BMFF box tree. Only structural boxes are decoded; unknown boxes stay byte-for-byte intact.
private struct MP4Box {
    var type: String
    var payload: Data
    var children: [MP4Box]?

    init(type: String, payload: Data, children: [MP4Box]? = nil) {
        self.type = type
        self.payload = payload
        self.children = children
    }

    func encoded() throws -> Data {
        var body = payload
        if let children {
            body = Data()
            for child in children { body.append(try child.encoded()) }
        }
        let totalSize = body.count + 8
        guard totalSize <= Int(UInt32.max) else { throw MP4PatchError.sizeLimit }
        var result = Data()
        result.appendBE(UInt32(totalSize))
        result.append(contentsOf: type.utf8.prefix(4))
        result.append(body)
        return result
    }

    func child(_ type: String) -> MP4Box? {
        children?.first(where: { $0.type == type })
    }
}

private struct TopLevelBox {
    let type: String
    let offset: Int64
    let size: Int64
    let headerSize: Int64
}

/// Native Swift implementation of the MP4 sample-table transformation used by khaled-cli HQ.
/// It appends one tiny filler NAL and makes each declared padding frame reference that sample.
/// The media payload is streamed to disk, so large files are not copied into a second in-memory buffer.
enum MP4Patcher {
    private static let containerTypes: Set<String> = ["moov", "trak", "mdia", "minf", "stbl", "edts", "dinf"]
    private static let fillerNAL = Data([0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00])
    private static let maximumPaddingFrames = 2_000_000

    static func transform(inputURL: URL, outputURL: URL, multiplier: Int = 10) throws -> MP4PatchReport {
        guard multiplier >= 2 && multiplier <= 20 else {
            throw MP4PatchError.unsupported("معامل الفريمات يجب أن يكون بين 2 و20")
        }
        let inputHandle = try FileHandle(forReadingFrom: inputURL)
        defer { try? inputHandle.close() }
        let fileSize = try inputHandle.seekToEnd()
        guard fileSize <= Int64(UInt32.max) - 64 * 1024 * 1024 else { throw MP4PatchError.sizeLimit }
        try inputHandle.seek(toOffset: 0)
        let mapped = try Data(contentsOf: inputURL, options: [.mappedIfSafe])
        let top = try parseTopLevel(mapped)
        guard let ftypBox = top.first(where: { $0.type == "ftyp" }) else { throw MP4PatchError.missing("ftyp") }
        guard let moovBox = top.first(where: { $0.type == "moov" }) else { throw MP4PatchError.missing("moov") }
        guard let mdatBox = top.first(where: { $0.type == "mdat" }) else { throw MP4PatchError.missing("mdat") }
        guard top.filter({ $0.type == "mdat" }).count == 1 else {
            throw MP4PatchError.unsupported("الملفات التي تحتوي أكثر من mdat غير مدعومة")
        }
        guard mdatBox.headerSize == 8 else {
            throw MP4PatchError.unsupported("حاوية mdat الممتدة غير مدعومة")
        }

        let oldMdatDataStart = mdatBox.offset + mdatBox.headerSize
        let oldMdatDataLength = mdatBox.size - mdatBox.headerSize
        let moovRange = Int(moovBox.offset)..<Int(moovBox.offset + moovBox.size)
        let moovBytes = mapped.subdata(in: moovRange)
        var moov = try parseSingleBox(moovBytes)
        guard moov.type == "moov", moov.children != nil else { throw MP4PatchError.malformed("moov") }

        let originalTracks = moov.children ?? []
        var videoTrackIndex: Int?
        for (index, item) in originalTracks.enumerated() where item.type == "trak" {
            if try handlerType(in: item) == "vide" { videoTrackIndex = index; break }
        }
        guard let videoTrackIndex else { throw MP4PatchError.missing("مسار الفيديو") }

        let originalVideoTrack = originalTracks[videoTrackIndex]
        let originalVideoTables = try sampleTables(in: originalVideoTrack)
        let frameCount = originalVideoTables.sampleSizes.count
        guard frameCount > 0 else { throw MP4PatchError.malformed("عدد الفريمات صفر") }
        let insertedFrames = frameCount * (multiplier - 1)
        guard insertedFrames <= maximumPaddingFrames else { throw MP4PatchError.unsupported("الفيديو طويل جدًا للمعالجة الآمنة") }
        guard originalVideoTables.chunkOffsets.count > 0 else { throw MP4PatchError.malformed("جدول stco فارغ") }

        let sttsEntries = try parseTimeToSamples(originalVideoTables.stts.payload)
        guard !sttsEntries.isEmpty,
              sttsEntries.allSatisfy({ $0.delta == sttsEntries[0].delta }),
              sttsEntries.reduce(0, { $0 + Int($1.count) }) == frameCount else {
            throw MP4PatchError.unsupported("المصدر ليس بمعدل فريمات ثابت")
        }
        let delta = sttsEntries[0].delta

        // Every existing media chunk must point into the one mdat we are relocating.
        var oldOffsetsByTrack: [Int: [UInt64]] = [:]
        var videoChunkTableType = "stco"
        for (index, item) in originalTracks.enumerated() where item.type == "trak" {
            guard let tables = try? sampleTables(in: item, requireVideoTables: false) else { continue }
            guard !tables.chunkOffsets.isEmpty else { continue }
            for offset in tables.chunkOffsets {
                guard offset >= UInt64(oldMdatDataStart),
                      offset < UInt64(oldMdatDataStart + oldMdatDataLength) else {
                    throw MP4PatchError.unsupported("جدول المقاطع يشير إلى بيانات خارج mdat")
                }
            }
            oldOffsetsByTrack[index] = tables.chunkOffsets
            if index == videoTrackIndex { videoChunkTableType = tables.chunkOffsetBox.type }
        }
        guard oldOffsetsByTrack[videoTrackIndex] != nil else {
            throw MP4PatchError.missing("إزاحات مقاطع الفيديو")
        }

        // Update video sample tables, but temporarily zero all chunk offsets. Their count determines moov size.
        var children = moov.children ?? []
        var updatedVideoTrack = children[videoTrackIndex]
        try updateVideoTables(track: &updatedVideoTrack, frameCount: frameCount,
                              insertedFrames: insertedFrames, delta: delta)
        children[videoTrackIndex] = updatedVideoTrack
        moov.children = children

        // Replace all chunk offset tables with same-sized placeholders (including the new filler-frame chunks).
        for index in children.indices where children[index].type == "trak" {
            guard let originalOffsets = oldOffsetsByTrack[index] else { continue }
            let count = originalOffsets.count + (index == videoTrackIndex ? insertedFrames : 0)
            try setChunkOffsets(track: &children[index], offsets: Array(repeating: 0, count: count),
                                preferredType: index == videoTrackIndex ? videoChunkTableType : nil)
        }
        moov.children = children
        let firstPassMoov = try moov.encoded()
        let ftypData = mapped.subdata(in: Int(ftypBox.offset)..<Int(ftypBox.offset + ftypBox.size))
        let freeData = Data([0x00, 0x00, 0x00, 0x08, 0x66, 0x72, 0x65, 0x65])
        let newMdatDataStart = UInt64(ftypData.count + freeData.count + firstPassMoov.count + 8)
        let fillerAbsoluteOffset = newMdatDataStart + UInt64(oldMdatDataLength)

        // Convert source absolute offsets to offsets in the relocated mdat; all padding frames share the filler sample.
        for index in children.indices where children[index].type == "trak" {
            guard let oldOffsets = oldOffsetsByTrack[index] else { continue }
            var updated: [UInt64] = oldOffsets.map { newMdatDataStart + ($0 - UInt64(oldMdatDataStart)) }
            if index == videoTrackIndex { updated.append(contentsOf: Array(repeating: fillerAbsoluteOffset, count: insertedFrames)) }
            try setChunkOffsets(track: &children[index], offsets: updated,
                                preferredType: index == videoTrackIndex ? videoChunkTableType : nil)
        }
        moov.children = children
        let finalMoovData = try moov.encoded()
        guard finalMoovData.count == firstPassMoov.count else {
            throw MP4PatchError.malformed("تغيّر حجم moov أثناء بناء الإزاحات")
        }
        let newMdatSize = Int64(mdatBox.size + Int64(fillerNAL.count))
        guard newMdatSize <= Int64(UInt32.max) else { throw MP4PatchError.sizeLimit }
        var mdatHeader = Data()
        mdatHeader.appendBE(UInt32(newMdatSize))
        mdatHeader.append(contentsOf: "mdat".utf8)

        try? FileManager.default.removeItem(at: outputURL)
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else { throw MP4PatchError.malformed("تعذّر إنشاء ملف الناتج") }
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle.close() }
        try outputHandle.write(contentsOf: ftypData)
        try outputHandle.write(contentsOf: freeData)
        try outputHandle.write(contentsOf: finalMoovData)
        try outputHandle.write(contentsOf: mdatHeader)
        try copyRange(from: inputHandle, to: outputHandle, start: oldMdatDataStart, length: oldMdatDataLength)
        try outputHandle.write(contentsOf: fillerNAL)
        try outputHandle.synchronize()

        // Basic structural sanity checks before returning success.
        let outputSize = try outputHandle.seekToEnd()
        guard outputSize >= fileSize, outputSize > 0 else { throw MP4PatchError.malformed("حجم الناتج غير متوقع") }
        let verifiedSize = try verifyOutput(outputURL, expectedFrames: frameCount + insertedFrames)
        guard UInt64(verifiedSize) == outputSize else { throw MP4PatchError.malformed("حجم الناتج تغيّر أثناء التحقق") }
        return MP4PatchReport(originalFrames: frameCount, declaredFrames: frameCount + insertedFrames,
                              insertedFrames: insertedFrames, outputBytes: Int64(outputSize))
    }

    private struct Tables {
        let stts: MP4Box
        let stsc: MP4Box
        let stsz: MP4Box
        let chunkOffsetBox: MP4Box
        let sampleSizes: [UInt32]
        let chunkOffsets: [UInt64]
    }

    private struct TimeRun {
        let count: UInt32
        let delta: UInt32
    }

    private static func verifyOutput(_ url: URL, expectedFrames: Int) throws -> Int64 {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let top = try parseTopLevel(data)
        guard let moovBox = top.first(where: { $0.type == "moov" }),
              let mdatBox = top.first(where: { $0.type == "mdat" }),
              top.filter({ $0.type == "mdat" }).count == 1,
              mdatBox.headerSize == 8 else {
            throw MP4PatchError.malformed("تعذّر إعادة قراءة بنية الناتج")
        }
        let moovBytes = data.subdata(in: Int(moovBox.offset)..<Int(moovBox.offset + moovBox.size))
        let moov = try parseSingleBox(moovBytes)
        let tracks = moov.children ?? []
        var video: MP4Box?
        for track in tracks where track.type == "trak" {
            if try handlerType(in: track) == "vide" { video = track; break }
        }
        guard let video else { throw MP4PatchError.missing("مسار الفيديو بعد المعالجة") }
        let tables = try sampleTables(in: video)
        guard tables.sampleSizes.count == expectedFrames else {
            throw MP4PatchError.malformed("عدد عينات الفيديو بعد المعالجة لا يطابق المتوقع")
        }
        let runs = try parseTimeToSamples(tables.stts.payload)
        guard runs.reduce(0, { $0 + Int($1.count) }) == expectedFrames else {
            throw MP4PatchError.malformed("جدول توقيت الإطارات غير متطابق")
        }
        let mdatStart = UInt64(mdatBox.offset + mdatBox.headerSize)
        let mdatEnd = UInt64(mdatBox.offset + mdatBox.size)
        for track in tracks where track.type == "trak" {
            guard let trackTables = try? sampleTables(in: track, requireVideoTables: false) else { continue }
            for offset in trackTables.chunkOffsets where offset < mdatStart || offset >= mdatEnd {
                throw MP4PatchError.malformed("إزاحة عينة خارج mdat في الناتج")
            }
        }
        return Int64(data.count)
    }

    private static func parseTopLevel(_ data: Data) throws -> [TopLevelBox] {
        var result: [TopLevelBox] = []
        var offset = 0
        while offset + 8 <= data.count {
            let rawSize = Int(try data.readBEUInt32(at: offset))
            let type = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
            var size = Int64(rawSize)
            var header: Int64 = 8
            if rawSize == 1 {
                guard offset + 16 <= data.count else { throw MP4PatchError.malformed("extended box header") }
                let extended = try data.readBEUInt64(at: offset + 8)
                guard extended <= UInt64(Int64.max) else { throw MP4PatchError.sizeLimit }
                size = Int64(extended)
                header = 16
            } else if rawSize == 0 {
                size = Int64(data.count - offset)
            }
            guard size >= header, size <= Int64(data.count - offset) else {
                throw MP4PatchError.malformed("box \(type) في الموضع \(offset)")
            }
            result.append(TopLevelBox(type: type, offset: Int64(offset), size: size, headerSize: header))
            offset += Int(size)
        }
        guard offset == data.count else { throw MP4PatchError.malformed("بيانات زائدة في نهاية الملف") }
        return result
    }

    private static func parseSingleBox(_ data: Data) throws -> MP4Box {
        let boxes = try parseBoxes(data, range: 0..<data.count)
        guard boxes.count == 1 else { throw MP4PatchError.malformed("توقّعت صندوقًا واحدًا") }
        return boxes[0]
    }

    private static func parseBoxes(_ data: Data, range: Range<Int>) throws -> [MP4Box] {
        var boxes: [MP4Box] = []
        var offset = range.lowerBound
        while offset + 8 <= range.upperBound {
            let rawSize = Int(try data.readBEUInt32(at: offset))
            let type = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
            var headerSize = 8
            var size = rawSize
            if rawSize == 1 {
                guard offset + 16 <= range.upperBound else { throw MP4PatchError.malformed("extended box") }
                let extended = try data.readBEUInt64(at: offset + 8)
                guard extended <= UInt64(Int.max) else { throw MP4PatchError.sizeLimit }
                size = Int(extended)
                headerSize = 16
            } else if rawSize == 0 {
                size = range.upperBound - offset
            }
            guard size >= headerSize, offset + size <= range.upperBound else {
                throw MP4PatchError.malformed("box \(type)")
            }
            let bodyRange = (offset + headerSize)..<(offset + size)
            if containerTypes.contains(type) {
                boxes.append(MP4Box(type: type, payload: Data(), children: try parseBoxes(data, range: bodyRange)))
            } else {
                boxes.append(MP4Box(type: type, payload: data.subdata(in: bodyRange), children: nil))
            }
            offset += size
        }
        guard offset == range.upperBound else { throw MP4PatchError.malformed("حدود الصناديق غير متطابقة") }
        return boxes
    }

    private static func handlerType(in track: MP4Box) throws -> String? {
        guard let mdia = track.child("mdia"), let hdlr = mdia.child("hdlr"), hdlr.payload.count >= 12 else { return nil }
        return String(decoding: hdlr.payload[8..<12], as: UTF8.self)
    }

    private static func sampleTables(in track: MP4Box, requireVideoTables: Bool = true) throws -> Tables {
        guard let mdia = track.child("mdia"), let minf = mdia.child("minf"), let stbl = minf.child("stbl") else {
            throw MP4PatchError.missing("stbl")
        }
        guard let stts = stbl.child("stts"), let stsc = stbl.child("stsc"),
              let stsz = stbl.child("stsz"),
              let offsetTable = stbl.child("stco") ?? stbl.child("co64") else {
            throw MP4PatchError.missing("جداول عينات الفيديو")
        }
        let sampleSizes = try parseSampleSizes(stsz.payload)
        let chunkOffsets = try parseChunkOffsets(offsetTable)
        if requireVideoTables && (sampleSizes.isEmpty || chunkOffsets.isEmpty) {
            throw MP4PatchError.malformed("جداول عينات الفيديو فارغة")
        }
        return Tables(stts: stts, stsc: stsc, stsz: stsz, chunkOffsetBox: offsetTable,
                      sampleSizes: sampleSizes, chunkOffsets: chunkOffsets)
    }

    private static func parseSampleSizes(_ payload: Data) throws -> [UInt32] {
        guard payload.count >= 12 else { throw MP4PatchError.malformed("stsz") }
        let uniformSize = try payload.readBEUInt32(at: 4)
        let count = Int(try payload.readBEUInt32(at: 8))
        guard count <= maximumPaddingFrames * 5 else { throw MP4PatchError.unsupported("عدد عينات غير منطقي") }
        if uniformSize != 0 { return Array(repeating: uniformSize, count: count) }
        guard payload.count >= 12 + count * 4 else { throw MP4PatchError.malformed("stsz entries") }
        return try (0..<count).map { try payload.readBEUInt32(at: 12 + $0 * 4) }
    }

    private static func parseChunkOffsets(_ box: MP4Box) throws -> [UInt64] {
        let payload = box.payload
        guard payload.count >= 8 else { throw MP4PatchError.malformed(box.type) }
        let count = Int(try payload.readBEUInt32(at: 4))
        let itemSize = box.type == "co64" ? 8 : 4
        guard payload.count >= 8 + count * itemSize else { throw MP4PatchError.malformed("\(box.type) entries") }
        return try (0..<count).map { index in
            box.type == "co64" ? try payload.readBEUInt64(at: 8 + index * itemSize) : UInt64(try payload.readBEUInt32(at: 8 + index * itemSize))
        }
    }

    private static func parseTimeToSamples(_ payload: Data) throws -> [TimeRun] {
        guard payload.count >= 8 else { throw MP4PatchError.malformed("stts") }
        let count = Int(try payload.readBEUInt32(at: 4))
        guard count > 0, payload.count >= 8 + count * 8 else { throw MP4PatchError.malformed("stts entries") }
        return try (0..<count).map { index in
            TimeRun(count: try payload.readBEUInt32(at: 8 + index * 8),
                    delta: try payload.readBEUInt32(at: 12 + index * 8))
        }
    }

    private static func updateVideoTables(track: inout MP4Box, frameCount: Int,
                                          insertedFrames: Int, delta: UInt32) throws {
        guard var trackChildren = track.children,
              let mdiaIndex = trackChildren.firstIndex(where: { $0.type == "mdia" }),
              var mdiaChildren = trackChildren[mdiaIndex].children,
              let minfIndex = mdiaChildren.firstIndex(where: { $0.type == "minf" }),
              var minfChildren = mdiaChildren[minfIndex].children,
              let stblIndex = minfChildren.firstIndex(where: { $0.type == "stbl" }),
              var stblChildren = minfChildren[stblIndex].children else {
            throw MP4PatchError.missing("جدول عينات الفيديو")
        }
        for i in stblChildren.indices {
            switch stblChildren[i].type {
            case "stts":
                stblChildren[i].payload = makeSTTS([(UInt32(frameCount), delta), (UInt32(insertedFrames), delta)])
                stblChildren[i].children = nil
            case "stsc":
                let oldEntries = try parseSampleToChunks(stblChildren[i].payload)
                let oldOffsets = try parseChunkOffsets(stblChildren.first(where: { $0.type == "stco" }) ?? stblChildren.first(where: { $0.type == "co64" }) ?? MP4Box(type: "stco", payload: Data()))
                var entries = oldEntries
                entries.append((UInt32(oldOffsets.count + 1), 1, 1))
                stblChildren[i].payload = makeSTSC(entries)
                stblChildren[i].children = nil
            case "stsz":
                let oldSizes = try parseSampleSizes(stblChildren[i].payload)
                guard oldSizes.count == frameCount else { throw MP4PatchError.malformed("sample count") }
                stblChildren[i].payload = makeSTSZ(oldSizes + Array(repeating: UInt32(fillerNAL.count), count: insertedFrames))
                stblChildren[i].children = nil
            default: break
            }
        }
        minfChildren[stblIndex].children = stblChildren
        mdiaChildren[minfIndex].children = minfChildren
        trackChildren[mdiaIndex].children = mdiaChildren
        track.children = trackChildren
    }

    private static func parseSampleToChunks(_ payload: Data) throws -> [(UInt32, UInt32, UInt32)] {
        guard payload.count >= 8 else { throw MP4PatchError.malformed("stsc") }
        let count = Int(try payload.readBEUInt32(at: 4))
        guard payload.count >= 8 + count * 12 else { throw MP4PatchError.malformed("stsc entries") }
        return try (0..<count).map { index in
            (try payload.readBEUInt32(at: 8 + index * 12),
             try payload.readBEUInt32(at: 12 + index * 12),
             try payload.readBEUInt32(at: 16 + index * 12))
        }
    }

    private static func setChunkOffsets(track: inout MP4Box, offsets: [UInt64], preferredType: String?) throws {
        guard var trackChildren = track.children,
              let mdiaIndex = trackChildren.firstIndex(where: { $0.type == "mdia" }),
              var mdiaChildren = trackChildren[mdiaIndex].children,
              let minfIndex = mdiaChildren.firstIndex(where: { $0.type == "minf" }),
              var minfChildren = mdiaChildren[minfIndex].children,
              let stblIndex = minfChildren.firstIndex(where: { $0.type == "stbl" }),
              var stblChildren = minfChildren[stblIndex].children else { return }
        guard let tableIndex = stblChildren.firstIndex(where: { $0.type == "stco" || $0.type == "co64" }) else { return }
        let original = stblChildren[tableIndex]
        let type = preferredType ?? original.type
        if type == "stco" && offsets.contains(where: { $0 > UInt64(UInt32.max) }) {
            throw MP4PatchError.sizeLimit
        }
        stblChildren[tableIndex] = MP4Box(type: type, payload: makeChunkOffsetPayload(offsets, type: type))
        minfChildren[stblIndex].children = stblChildren
        mdiaChildren[minfIndex].children = minfChildren
        trackChildren[mdiaIndex].children = mdiaChildren
        track.children = trackChildren
    }

    private static func makeSTTS(_ entries: [(UInt32, UInt32)]) -> Data {
        var data = Data([0, 0, 0, 0])
        data.appendBE(UInt32(entries.count))
        for entry in entries { data.appendBE(entry.0); data.appendBE(entry.1) }
        return data
    }

    private static func makeSTSC(_ entries: [(UInt32, UInt32, UInt32)]) -> Data {
        var data = Data([0, 0, 0, 0])
        data.appendBE(UInt32(entries.count))
        for entry in entries { data.appendBE(entry.0); data.appendBE(entry.1); data.appendBE(entry.2) }
        return data
    }

    private static func makeSTSZ(_ sizes: [UInt32]) -> Data {
        var data = Data([0, 0, 0, 0])
        data.appendBE(UInt32(0))
        data.appendBE(UInt32(sizes.count))
        for size in sizes { data.appendBE(size) }
        return data
    }

    private static func makeChunkOffsetPayload(_ offsets: [UInt64], type: String) -> Data {
        var data = Data([0, 0, 0, 0])
        data.appendBE(UInt32(offsets.count))
        for offset in offsets {
            if type == "co64" { data.appendBE(offset) }
            else { data.appendBE(UInt32(offset)) }
        }
        return data
    }

    private static func copyRange(from input: FileHandle, to output: FileHandle,
                                  start: Int64, length: Int64) throws {
        try input.seek(toOffset: UInt64(start))
        var remaining = length
        while remaining > 0 {
            let amount = Int(min(1_048_576, remaining))
            guard let chunk = try input.read(upToCount: amount), !chunk.isEmpty else {
                throw MP4PatchError.malformed("انتهت بيانات mdat قبل المتوقع")
            }
            try output.write(contentsOf: chunk)
            remaining -= Int64(chunk.count)
        }
    }
}

private extension Data {
    mutating func appendBE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xff)); append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff)); append(UInt8(value & 0xff))
    }

    mutating func appendBE(_ value: UInt64) {
        appendBE(UInt32((value >> 32) & 0xffff_ffff)); appendBE(UInt32(value & 0xffff_ffff))
    }

    func readBEUInt32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw MP4PatchError.malformed("قراءة خارج حدود البيانات") }
        return (UInt32(self[index(startIndex, offsetBy: offset)]) << 24)
            | (UInt32(self[index(startIndex, offsetBy: offset + 1)]) << 16)
            | (UInt32(self[index(startIndex, offsetBy: offset + 2)]) << 8)
            | UInt32(self[index(startIndex, offsetBy: offset + 3)])
    }

    func readBEUInt64(at offset: Int) throws -> UInt64 {
        let high = UInt64(try readBEUInt32(at: offset))
        let low = UInt64(try readBEUInt32(at: offset + 4))
        return (high << 32) | low
    }
}
