import AVFoundation
import CoreGraphics
import Foundation

struct VideoProcessingResult {
    let outputURL: URL
    let frameCount: Int
    let declaredFrameCount: Int
    let fileSize: Int64
}

enum VideoProcessingError: LocalizedError {
    case noVideoTrack
    case noExportPreset
    case unsupportedCodec
    case exportFailed(String)
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "المقطع ما يحتوي على مسار فيديو قابل للقراءة."
        case .noExportPreset: return "ما قدرت ألقى إعداد تصدير مناسب لهذا المقطع."
        case .unsupportedCodec: return "التصدير ما أنتج فيديو H.264 المطلوب للمعالجة. جرّب مقطعًا آخر أو دقة أقل."
        case .exportFailed(let reason): return "فشل تجهيز الفيديو: \(reason)"
        case .verificationFailed(let reason): return "فشل فحص الناتج: \(reason)"
        }
    }
}

enum VideoProcessor {
    @MainActor
    static func process(inputURL: URL, requestedShortEdge: Int,
                        progress: @escaping @MainActor (Double, String) -> Void) async throws -> VideoProcessingResult {
        let asset = AVURLAsset(url: inputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw VideoProcessingError.noVideoTrack }
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)
        guard duration.isNumeric, duration.seconds > 0 else {
            throw VideoProcessingError.verificationFailed("مدة الفيديو غير صالحة")
        }

        let geometry = outputGeometry(naturalSize: naturalSize, transform: preferredTransform,
                                      requestedShortEdge: requestedShortEdge)
        let frameDuration = normalizedFrameDuration(nominalFrameRate)
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("KhaledHQ-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let preparedURL = tempRoot.appendingPathComponent("prepared.mp4")
        progress(0.03, "فحص المقطع الأصلي")
        let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let desiredPreset: String
        if geometry.shortEdge >= 2160 && presets.contains(AVAssetExportPreset3840x2160) {
            desiredPreset = AVAssetExportPreset3840x2160
        } else if geometry.shortEdge <= 1080 && presets.contains(AVAssetExportPreset1920x1080) {
            desiredPreset = AVAssetExportPreset1920x1080
        } else if presets.contains(AVAssetExportPresetHighestQuality) {
            desiredPreset = AVAssetExportPresetHighestQuality
        } else if let first = presets.first {
            desiredPreset = first
        } else {
            throw VideoProcessingError.noExportPreset
        }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: desiredPreset) else {
            throw VideoProcessingError.noExportPreset
        }
        guard exporter.supportedFileTypes.contains(.mp4) else {
            throw VideoProcessingError.exportFailed("المقطع لا يدعم تصدير MP4 على هذا الجهاز")
        }
        exporter.outputURL = preparedURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true

        let composition = AVMutableVideoComposition()
        composition.renderSize = geometry.size
        composition.frameDuration = frameDuration
        composition.renderScale = 1
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(geometry.transform, at: .zero)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]
        exporter.videoComposition = composition

        progress(0.08, "إعادة ترميز الفيديو إلى H.264")
        let exportTask = Task<Void, Error> {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                exporter.exportAsynchronously {
                    switch exporter.status {
                    case .completed:
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    case .failed:
                        continuation.resume(throwing: VideoProcessingError.exportFailed(exporter.error?.localizedDescription ?? "سبب غير معروف"))
                    default:
                        continuation.resume(throwing: VideoProcessingError.exportFailed(exporter.error?.localizedDescription ?? "انتهى التصدير بحالة غير متوقعة"))
                    }
                }
            }
        }
        while ![AVAssetExportSession.Status.completed, .failed, .cancelled].contains(exporter.status) {
            progress(0.08 + min(0.65, Double(exporter.progress) * 0.65), "إعادة ترميز الفيديو إلى H.264")
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        try await exportTask.value

        guard FileManager.default.fileExists(atPath: preparedURL.path) else {
            throw VideoProcessingError.exportFailed("ملف الفيديو المؤقت غير موجود")
        }
        let preparedAsset = AVURLAsset(url: preparedURL)
        let preparedTracks = try await preparedAsset.loadTracks(withMediaType: .video)
        guard let preparedVideo = preparedTracks.first else { throw VideoProcessingError.unsupportedCodec }
        let formatDescriptions = try await preparedVideo.load(.formatDescriptions)
        let hasH264 = formatDescriptions.contains { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 }
        guard hasH264 else { throw VideoProcessingError.unsupportedCodec }

        progress(0.78, "تطبيق معالجة MP4")
        let folder = try outputFolder()
        let label = geometry.shortEdge >= 2160 ? "4K" : (geometry.shortEdge >= 1440 ? "1440p" : "1080p")
        let outputURL = uniqueOutputURL(in: folder,
            baseName: inputURL.deletingPathExtension().lastPathComponent + "_\(label)_khaled_cli")
        let report = try MP4Patcher.transform(inputURL: preparedURL, outputURL: outputURL, multiplier: 10)

        progress(0.93, "فحص الملف النهائي")
        let finalAsset = AVURLAsset(url: outputURL)
        let finalVideoTracks = try await finalAsset.loadTracks(withMediaType: .video)
        guard !finalVideoTracks.isEmpty else {
            try? FileManager.default.removeItem(at: outputURL)
            throw VideoProcessingError.verificationFailed("مسار الفيديو اختفى بعد المعالجة")
        }
        let finalDuration = try await finalAsset.load(.duration)
        guard finalDuration.isNumeric, finalDuration.seconds > 0,
              abs(finalDuration.seconds - duration.seconds) < max(1.0, duration.seconds * 0.02) else {
            try? FileManager.default.removeItem(at: outputURL)
            throw VideoProcessingError.verificationFailed("تغيّرت مدة الفيديو بشكل غير متوقع")
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let bytes = (attrs[.size] as? NSNumber)?.int64Value ?? report.outputBytes
        progress(1, "اكتمل الفحص")
        return VideoProcessingResult(outputURL: outputURL, frameCount: report.originalFrames,
                                     declaredFrameCount: report.declaredFrames, fileSize: bytes)
    }

    private struct Geometry {
        let size: CGSize
        let transform: CGAffineTransform
        let shortEdge: Int
    }

    private static func outputGeometry(naturalSize: CGSize, transform: CGAffineTransform,
                                       requestedShortEdge: Int) -> Geometry {
        let sourceRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let orientedWidth = max(2, abs(sourceRect.width))
        let orientedHeight = max(2, abs(sourceRect.height))
        let sourceShortEdge = min(orientedWidth, orientedHeight)
        let scale = min(1, CGFloat(requestedShortEdge) / sourceShortEdge)
        let width = evenDimension(orientedWidth * scale)
        let height = evenDimension(orientedHeight * scale)
        var outputTransform = transform
        outputTransform.tx -= sourceRect.minX
        outputTransform.ty -= sourceRect.minY
        outputTransform = CGAffineTransform(a: outputTransform.a * scale,
                                            b: outputTransform.b * scale,
                                            c: outputTransform.c * scale,
                                            d: outputTransform.d * scale,
                                            tx: outputTransform.tx * scale,
                                            ty: outputTransform.ty * scale)
        return Geometry(size: CGSize(width: width, height: height), transform: outputTransform,
                        shortEdge: Int(min(width, height)))
    }

    private static func evenDimension(_ value: CGFloat) -> CGFloat {
        let rounded = max(2, Int(value.rounded()))
        return CGFloat(rounded.isMultiple(of: 2) ? rounded : rounded - 1)
    }

    private static func normalizedFrameDuration(_ inputRate: Float) -> CMTime {
        let candidates: [(Float, CMTime)] = [
            (23.976, CMTime(value: 1001, timescale: 24000)),
            (24, CMTime(value: 1, timescale: 24)),
            (25, CMTime(value: 1, timescale: 25)),
            (29.97, CMTime(value: 1001, timescale: 30000)),
            (30, CMTime(value: 1, timescale: 30)),
            (48, CMTime(value: 1, timescale: 48)),
            (50, CMTime(value: 1, timescale: 50)),
            (59.94, CMTime(value: 1001, timescale: 60000)),
            (60, CMTime(value: 1, timescale: 60)),
            (100, CMTime(value: 1, timescale: 100)),
            (119.88, CMTime(value: 1001, timescale: 120000)),
            (120, CMTime(value: 1, timescale: 120))
        ]
        let value = inputRate.isFinite && inputRate > 0 ? inputRate : 30
        return candidates.min(by: { abs($0.0 - value) < abs($1.0 - value) })?.1 ?? CMTime(value: 1, timescale: 30)
    }

    private static func outputFolder() throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("Khaled HQ", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func uniqueOutputURL(in folder: URL, baseName: String) -> URL {
        var candidate = folder.appendingPathComponent(baseName).appendingPathExtension("mp4")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(baseName) (\(suffix))").appendingPathExtension("mp4")
            suffix += 1
        }
        return candidate
    }
}
