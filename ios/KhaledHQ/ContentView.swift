import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

private enum HQPalette {
    static let background = Color(red: 0.075, green: 0.078, blue: 0.075)
    static let panel = Color(red: 0.12, green: 0.125, blue: 0.12)
    static let edge = Color(red: 0.22, green: 0.22, blue: 0.21)
    static let amber = Color(red: 0.94, green: 0.62, blue: 0.15)
    static let green = Color(red: 0.59, green: 0.77, blue: 0.35)
    static let secondary = Color(red: 0.69, green: 0.68, blue: 0.64)
}

private struct ImportedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let source = received.file
            let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("KhaledHQ-import-\(UUID().uuidString)")
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: source, to: destination)
            return ImportedMovie(url: destination)
        }
    }
}

struct ContentView: View {
    @State private var photoItem: PhotosPickerItem?
    @State private var inputURL: URL?
    @State private var inputName = ""
    @State private var outputURL: URL?
    @State private var requestedResolution = 2160
    @State private var isProcessing = false
    @State private var progress = 0.0
    @State private var statusText = "اختر مقطعًا للبدء"
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var showFileImporter = false
    @State private var resultSummary = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    purposeCard
                    sourceCard
                    resolutionCard
                    processButton
                    if isProcessing { progressCard }
                    if let outputURL { outputCard(url: outputURL) }
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(HQPalette.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.movie, .mpeg4Movie],
                          allowsMultipleSelection: false,
                          onCompletion: handleFileImport)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await importFromPhotos(item) }
            }
            .alert("تعذّر تجهيز الفيديو", isPresented: $showError) {
                Button("حسنًا", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
        .tint(HQPalette.amber)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "film.stack")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HQPalette.amber)
                Text("KHALED CLI HQ")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(HQPalette.secondary)
                Spacer()
                Text("iOS · iPadOS")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(HQPalette.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("جهّز مقطعك")
                    .font(.system(size: 31, weight: .heavy, design: .serif))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            Text("تحويل فعلي للفيديو ثم معالجة بنية MP4 وفحص الناتج")
                .font(.system(size: 14))
                .foregroundStyle(HQPalette.secondary)
        }
        .padding(.top, 6)
    }

    private var purposeCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(HQPalette.amber)
                .frame(width: 42, height: 42)
                .background(HQPalette.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text("المعالجة تتم على جهازك")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("يُعاد ترميز المقطع إلى H.264، ثم تُطبّق معالجة MP4. ملفك الأصلي لا يتغيّر.")
                    .font(.system(size: 13))
                    .foregroundStyle(HQPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HQPalette.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(HQPalette.edge, lineWidth: 1))
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("01", title: "المقطع الأصلي")
            if let inputURL {
                HStack(spacing: 10) {
                    Image(systemName: "video.fill")
                        .foregroundStyle(HQPalette.green)
                        .frame(width: 38, height: 38)
                        .background(HQPalette.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(inputName.isEmpty ? inputURL.lastPathComponent : inputName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("جاهز للمعالجة")
                            .font(.system(size: 12))
                            .foregroundStyle(HQPalette.green)
                    }
                    Spacer(minLength: 4)
                    Button {
                        guard !isProcessing else { return }
                        self.inputURL = nil
                        self.inputName = ""
                        self.outputURL = nil
                        self.photoItem = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(HQPalette.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("إزالة المقطع المحدد")
                }
                .padding(12)
                .background(HQPalette.background, in: RoundedRectangle(cornerRadius: 12))
            } else {
                Text("يدعم مقاطع MOV وMP4 من الصور أو تطبيق الملفات.")
                    .font(.system(size: 13))
                    .foregroundStyle(HQPalette.secondary)
            }
            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .videos) {
                    Label("الصور", systemImage: "photo.on.rectangle")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(.black)
                        .background(HQPalette.amber, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isProcessing)
                Button {
                    showFileImporter = true
                } label: {
                    Label("الملفات", systemImage: "folder")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(.white)
                        .background(HQPalette.edge.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HQPalette.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(HQPalette.edge, lineWidth: 1))
    }

    private var resolutionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("02", title: "الدقة المستهدفة")
            HStack(spacing: 8) {
                resolutionChoice(value: 1080, title: "1080p", subtitle: "Full HD")
                resolutionChoice(value: 1440, title: "1440p", subtitle: "QHD")
                resolutionChoice(value: 2160, title: "4K", subtitle: "Ultra HD")
            }
            Text("التطبيق لا يكبّر المقطع الأصغر من الدقة المختارة. معدل الإطارات يُختار من معدلات قياسية حتى 120 إطارًا/ثانية، حسب المصدر ودعم الجهاز.")
                .font(.system(size: 12))
                .foregroundStyle(HQPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HQPalette.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(HQPalette.edge, lineWidth: 1))
    }

    private var processButton: some View {
        Button {
            Task { await startProcessing() }
        } label: {
            HStack(spacing: 10) {
                if isProcessing {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: "wand.and.stars")
                }
                Text(isProcessing ? "جارٍ تجهيز المقطع…" : "جهّز الفيديو")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                if !isProcessing { Image(systemName: "arrow.left") }
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 17)
            .padding(.vertical, 16)
            .background(inputURL == nil || isProcessing ? HQPalette.amber.opacity(0.45) : HQPalette.amber,
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(inputURL == nil || isProcessing)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(statusText).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                Spacer()
                Text("\(Int(progress * 100))٪")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(HQPalette.secondary)
            }
            ProgressView(value: progress)
                .tint(HQPalette.amber)
            Text("لا تغلق التطبيق أثناء معالجة الفيديو.")
                .font(.system(size: 11))
                .foregroundStyle(HQPalette.secondary)
        }
        .padding(15)
        .background(HQPalette.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private func outputCard(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(HQPalette.green)
                Text("اكتملت المعالجة والفحص")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(url.lastPathComponent)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(HQPalette.secondary)
                .textSelection(.enabled)
            if !resultSummary.isEmpty {
                Text(resultSummary)
                    .font(.system(size: 12))
                    .foregroundStyle(HQPalette.secondary)
            }
            ShareLink(item: url, preview: SharePreview(url.lastPathComponent)) {
                Label("حفظ أو مشاركة الناتج", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(.black)
                    .background(HQPalette.green, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HQPalette.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(HQPalette.green.opacity(0.35), lineWidth: 1))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(HQPalette.edge)
            Label("المعالجة محلية على الجهاز", systemImage: "lock.shield")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HQPalette.secondary)
            Text("تنبيه: معالجة الملف لا تضمن أن تيك توك سيعرضه بجودته الأصلية. طريقة الضغط قد تتغير من تيك توك نفسه.")
                .font(.system(size: 11))
                .foregroundStyle(HQPalette.secondary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    private func sectionLabel(_ number: String, title: String) -> some View {
        HStack(spacing: 9) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(HQPalette.amber)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(HQPalette.amber.opacity(0.12), in: Capsule())
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
        }
    }

    private func resolutionChoice(value: Int, title: String, subtitle: String) -> some View {
        let selected = requestedResolution == value
        return Button {
            requestedResolution = value
        } label: {
            VStack(spacing: 5) {
                Text(title).font(.system(size: 15, weight: .bold))
                Text(subtitle).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(selected ? .black.opacity(0.65) : HQPalette.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(selected ? .black : .white)
            .background(selected ? HQPalette.amber : HQPalette.background,
                        in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(selected ? HQPalette.amber : HQPalette.edge, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }

    @MainActor
    private func importFromPhotos(_ item: PhotosPickerItem) async {
        do {
            guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
                throw CocoaError(.fileReadUnknown)
            }
            setInput(url: movie.url)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    @MainActor
    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("KhaledHQ-import-\(UUID().uuidString)")
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: url, to: destination)
            setInput(url: destination)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    @MainActor
    private func setInput(url: URL) {
        if let previous = inputURL, previous.path.contains("KhaledHQ-import-") {
            try? FileManager.default.removeItem(at: previous)
        }
        inputURL = url
        inputName = url.lastPathComponent
        outputURL = nil
        resultSummary = ""
        progress = 0
        statusText = "المقطع جاهز للمعالجة"
    }

    @MainActor
    private func startProcessing() async {
        guard let inputURL, !isProcessing else { return }
        isProcessing = true
        progress = 0.02
        outputURL = nil
        resultSummary = ""
        defer { isProcessing = false }
        do {
            let result = try await VideoProcessor.process(inputURL: inputURL,
                                                          requestedShortEdge: requestedResolution) { value, text in
                self.progress = value
                self.statusText = text
            }
            outputURL = result.outputURL
            let mb = Double(result.fileSize) / 1_000_000
            resultSummary = "الإطارات الأصلية: \(result.frameCount.formatted()) · المعلنة بعد المعالجة: \(result.declaredFrameCount.formatted()) · الحجم: \(String(format: "%.1f", mb)) MB"
            statusText = "اكتمل الفحص"
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
