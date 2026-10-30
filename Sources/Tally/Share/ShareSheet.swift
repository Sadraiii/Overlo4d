import CoreTransferable
import PhotosUI
import SwiftUI
// SwiftUI's PhotosPicker lives in this cross-import overlay; Xcode adds it automatically, SwiftPM on Linux doesn't.
import _PhotosUI_SwiftUI
import TallyKit
import UniformTypeIdentifiers

/// PNG export for the share sheet (keeps sticker transparency).
struct SharePNG: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
            .suggestedFileName { $0.name }
    }
}

/// Preview and export a story image, a transparent sticker or plain text.
struct ShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: ShareModel

    enum Format: String, CaseIterable, Identifiable {
        case story = "Story"
        case sticker = "Sticker"
        case text = "Text"
        var id: String { rawValue }
    }

    private struct RenderKey: Hashable {
        let format: Format
        let palette: String
        let sticker: StickerColor
        let hidden: Set<SharePart>
        let photoVersion: Int
    }

    @State private var format = Format.story
    @State private var paletteID = "night"
    @State private var sticker = StickerColor.white
    @State private var hidden: Set<SharePart> = []
    @State private var photo: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var photoVersion = 0
    @State private var image: UIImage?
    @State private var copied = false

    private var accent: Accent { Theme.accentChoice }
    private var palettes: [StoryPalette] { StoryPalette.all(accent: accent) }

    private var palette: StoryPalette {
        paletteID == "photo" ? .photo(accent: accent) : palettes.first { $0.id == paletteID } ?? palettes[0]
    }

    /// Parts that exist for this content.
    private var parts: [SharePart] {
        SharePart.allCases.filter { part in
            switch part {
            case .hero: model.hero != nil
            case .stats: !model.stats.isEmpty
            case .days: model.days != nil
            case .lines: !model.lines.isEmpty
            default: true
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    preview
                    Segmented(selection: $format)
                    switch format {
                    case .story: backgrounds
                    case .sticker: stickerColors
                    case .text: EmptyView()
                    }
                    if format != .text { partToggles }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc", action: copy)
                        .buttonStyle(OOButtonStyle(kind: copied ? .done : .outline, shape: .pill, height: 58))
                    if format == .text {
                        ShareLink(item: model.plainText, subject: Text(model.title)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bigPrimary)
                    } else if let image, let data = image.pngData() {
                        ShareLink(
                            item: SharePNG(data: data, name: model.fileName),
                            preview: SharePreview(model.title, image: Image(uiImage: image))
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bigPrimary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(Theme.paper)
            }
            .task(id: RenderKey(format: format, palette: paletteID, sticker: sticker, hidden: hidden, photoVersion: photoVersion)) {
                render()
                copied = false
            }
            .onChange(of: photoItem) { loadPhoto() }
        }
    }

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        if format == .text {
            Text(model.plainText)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 14, cornerRadius: 20)
        } else {
            imagePreview
        }
    }

    private var imagePreview: some View {
        ZStack {
            if format == .sticker {
                Checkerboard(dark: sticker != .black)
                    .clipShape(.rect(cornerRadius: 18))
            }
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: format == .story ? 16 : 0))
                    .padding(format == .sticker ? 22 : 0)
            } else {
                ProgressView()
            }
        }
        .frame(height: 440)
        .frame(maxWidth: format == .story ? 248 : .infinity)
        .overlay {
            if format == .story {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(format == .story ? 0.18 : 0), radius: 16, y: 10)
        .frame(maxWidth: .infinity)
    }

    // MARK: Options

    private var backgrounds: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Background").eyebrow(11.5)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "photo")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 44)
                            .background(Theme.line, in: .circle)
                            .overlay(SelectionRing(selected: paletteID == "photo"))
                    }
                    ForEach(palettes) { option in
                        Button {
                            paletteID = option.id
                        } label: {
                            Circle()
                                .fill(option.bg)
                                .overlay(Circle().fill(option.acc).frame(width: 12, height: 12))
                                .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 1))
                                .frame(width: 44, height: 44)
                                .overlay(SelectionRing(selected: paletteID == option.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stickerColors: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Colour").eyebrow(11.5)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(StickerColor.allCases) { option in
                        Button {
                            sticker = option
                        } label: {
                            Circle()
                                .fill(option.fg)
                                .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 1))
                                .frame(width: 44, height: 44)
                                .overlay(SelectionRing(selected: sticker == option))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var partToggles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Show").eyebrow(11.5)
            FlowLayout(spacing: 8) {
                ForEach(parts) { part in
                    let shown = !hidden.contains(part)
                    Button {
                        if shown { hidden.insert(part) } else { hidden.remove(part) }
                    } label: {
                        Label(part.label, systemImage: shown ? "checkmark" : "plus")
                            .font(Typo.body(13.5, .semibold))
                            .foregroundStyle(shown ? Theme.paper : Theme.ink2)
                            .padding(.horizontal, 13)
                            .frame(minHeight: 36)
                            .background(shown ? Theme.ink : .clear, in: .capsule)
                            .overlay(Capsule().strokeBorder(shown ? .clear : Theme.line2, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private func render() {
        switch format {
        case .story:
            let renderer = ImageRenderer(content: StoryCard(model: model, palette: palette, photo: paletteID == "photo" ? photo : nil, hidden: hidden))
            renderer.proposedSize = ProposedViewSize(width: 1080, height: 1920)
            renderer.scale = 1
            image = renderer.uiImage
        case .sticker:
            let renderer = ImageRenderer(content: StickerCard(model: model, color: sticker, hidden: hidden))
            renderer.proposedSize = ProposedViewSize(width: 1080, height: nil)
            renderer.scale = 1
            renderer.isOpaque = false
            image = renderer.uiImage
        case .text:
            break
        }
    }

    private func copy() {
        if format == .text {
            UIPasteboard.general.string = model.plainText
        } else {
            guard let data = image?.pngData() else { return }
            UIPasteboard.general.setItems([[UTType.png.identifier: data]])
        }
        withAnimation(.snappy) { copied = true }
    }

    private func loadPhoto() {
        guard let photoItem else { return }
        Task {
            if let data = try? await photoItem.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
                photo = picked
                paletteID = "photo"
                photoVersion += 1
            }
        }
    }
}

/// Ring around the selected swatch.
struct SelectionRing: View {
    let selected: Bool

    var body: some View {
        Circle()
            .strokeBorder(Theme.ink, lineWidth: 2.5)
            .padding(-5)
            .opacity(selected ? 1 : 0)
    }
}

/// Transparency checkerboard behind sticker previews.
struct Checkerboard: View {
    let dark: Bool

    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 12
            let a = dark ? Color(red: 0.19, green: 0.21, blue: 0.18) : Color(red: 0.87, green: 0.88, blue: 0.85)
            let b = dark ? Color(red: 0.24, green: 0.26, blue: 0.24) : Color(red: 0.80, green: 0.82, blue: 0.78)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(a))
            for row in 0..<Int(size.height / cell) + 1 {
                for column in 0..<Int(size.width / cell) + 1 where (row + column) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)), with: .color(b))
                }
            }
        }
    }
}

/// Wraps children onto new lines, like CSS flex-wrap.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
