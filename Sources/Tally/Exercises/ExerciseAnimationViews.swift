import ImageIO
import SwiftUI
import TallyCore
import TallyKit
import UIKit

/// Turns GIF data into a UIImage that plays (or its first frame), kept in memory once decoded.
enum AnimatedGIF {
    nonisolated(unsafe) private static let memory = NSCache<NSString, UIImage>()

    static func image(_ data: Data, key: String, animated: Bool) -> UIImage? {
        let cacheKey = "\(key)-\(animated)" as NSString
        if let image = memory.object(forKey: cacheKey) { return image }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        // Decode at the size it's shown at, not the file's: a full-size GIF of 60+ frames costs
        // tens of megabytes, and stills only ever appear as small icons.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: animated ? 900 : 240,
        ]
        func frame(_ index: Int) -> CGImage? {
            CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(source, index, nil)
        }
        let image: UIImage?
        if animated && count > 1 {
            var frames: [UIImage] = []
            var duration = 0.0
            for index in 0..<count {
                guard let cgImage = frame(index) else { continue }
                frames.append(UIImage(cgImage: cgImage))
                duration += delay(source, index)
            }
            image = UIImage.animatedImage(with: frames, duration: duration)
        } else {
            image = frame(0).map { UIImage(cgImage: $0) }
        }
        if let image { memory.setObject(image, forKey: cacheKey) }
        return image
    }

    private static func delay(_ source: CGImageSource, _ index: Int) -> Double {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let value = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        // Browsers treat very short delays as 0.1 s; do the same so nothing plays too fast.
        return value < 0.02 ? 0.1 : value
    }

    /// Two photos (start and end position) flipping back and forth, or the first one only.
    static func flipbook(_ frames: [Data], key: String, animated: Bool) -> UIImage? {
        let cacheKey = "\(key)-\(animated)" as NSString
        if let image = memory.object(forKey: cacheKey) { return image }
        let images = frames.compactMap { UIImage(data: $0)?.preparingForDisplay() }
        guard let first = images.first else { return nil }
        let image = animated && images.count > 1 ? UIImage.animatedImage(with: images, duration: 2.4) : first
        if let image { memory.setObject(image, forKey: cacheKey) }
        return image
    }

    static func clearMemory() { memory.removeAllObjects() }
}

private struct GIFImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        if view.image !== image {
            view.image = image
            view.startAnimating()
        }
    }
}

/// A Workout API animation or Free Exercise DB photos, loaded from the phone or downloaded once.
/// Shows `placeholder` until it's ready.
struct ExerciseAnimation<Placeholder: View>: View {
    let media: ExerciseMedia
    var variant: WorkoutAPI.Variant = .basic
    /// false shows the first frame only, for small badges in lists.
    var animated = true
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: ExerciseMediaStore { .shared }

    private var key: String {
        switch media {
        case .workoutAPI(let code): ExerciseMediaStore.fileName(code, variant)
        case .photos(let id): "photos-\(id)"
        case .figure(let move, _): "figure-\(move.rawValue)"
        }
    }

    var body: some View {
        ZStack {
            if let image {
                GIFImageView(image: image)
            } else {
                placeholder()
            }
        }
        .task(id: "\(key)-\(animated && !reduceMotion)-\(store.failures.count)") {
            image = nil
            let key = key, animated = animated && !reduceMotion
            switch media {
            case .workoutAPI(let code):
                guard let data = await store.animation(code, variant) else { return }
                // Decoding every frame takes a moment, so keep it off the main thread while lists scroll.
                image = await Task.detached(priority: .userInitiated) {
                    AnimatedGIF.image(data, key: key, animated: animated)
                }.value
            case .photos(let id):
                guard let frames = await store.photos(id) else { return }
                image = await Task.detached(priority: .userInitiated) {
                    AnimatedGIF.flipbook(frames, key: key, animated: animated)
                }.value
            case .figure:
                break
            }
        }
    }
}

/// "How to do it": the demo on the exercise screen and the live workout sheet. A switch picks the
/// style (figure, photos, Workout API drawings) out of those this exercise has; the choice is
/// remembered. Every style sits on the same stage, so the card keeps its size while switching or
/// loading. What the exercise trains is the job of MuscleTargetsCard, not this one.
struct ExerciseDemoCard: View {
    let exercise: ExerciseDef
    /// Stage height; nil picks one for the screen width.
    var height: CGFloat?

    @AppStorage("workoutapi.variant") private var variantRaw = WorkoutAPI.Variant.basic.rawValue
    @State private var choosing = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var store: ExerciseMediaStore { .shared }
    private var variant: WorkoutAPI.Variant { WorkoutAPI.Variant(rawValue: variantRaw) ?? .basic }
    private var stageHeight: CGFloat { height ?? (sizeClass == .regular ? 380 : 260) }

    var body: some View {
        let options = store.available(for: exercise)
        let styles = ExerciseDemoStyle.allCases.filter { options[$0] != nil }
        let media = store.media(for: exercise)

        if media != nil || store.hasKey {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("How to do it").font(Typo.title(18)).foregroundStyle(Theme.ink)
                    Spacer()
                    if case .photos = media {
                        Text("Free Exercise DB").font(Typo.body(12)).foregroundStyle(Theme.ink3)
                    }
                }

                if styles.count > 1 {
                    let shown: ExerciseDemoStyle = switch media {
                    case .photos: .photos
                    case .workoutAPI: .drawings
                    default: .figure
                    }
                    Picker("Style", selection: Binding(get: { shown }, set: { store.style = $0 })) {
                        ForEach(styles) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                stage(media)

                if case .workoutAPI = media {
                    HStack(spacing: 8) {
                        Picker("Show", selection: $variantRaw) {
                            Text("Movement").tag(WorkoutAPI.Variant.basic.rawValue)
                            Text("Muscles").tag(WorkoutAPI.Variant.muscles.rawValue)
                        }
                        .pickerStyle(.segmented)
                        Button("Change") { choosing = true }
                            .font(Typo.body(14, .semibold))
                    }
                }
            }
            .card(padding: 14)
            .animation(.snappy, value: store.style)
            .task { await store.loadCatalogue() }
            .sheet(isPresented: $choosing) { AnimationChooser(exercise: exercise) }
        }
    }

    /// The demo itself, on a fixed-height stage. Drawings and photos are fitted, never cropped,
    /// so hands and feet stay in the picture.
    @ViewBuilder
    private func stage(_ media: ExerciseMedia?) -> some View {
        Group {
            switch media {
            case .figure(let move, let load):
                MotionFigureView(
                    move: move, load: load,
                    primary: Set(exercise.primary), secondary: Set(exercise.secondary)
                )
                .padding(.vertical, 8)
                .background(Theme.fill.opacity(0.6))
                .accessibilityElement()
                .accessibilityLabel("Animated figure doing \(exercise.name)")

            case .workoutAPI(let code):
                ExerciseAnimation(media: .workoutAPI(code: code), variant: variant) {
                    placeholder(ExerciseMediaStore.fileName(code, variant), media: .workoutAPI(code: code))
                }
                .padding(10)
                // The drawings are made for a white page, so they keep one in dark mode too.
                .background(.white)
                .accessibilityElement()
                .accessibilityLabel("Animation of \(exercise.name)")

            case .photos(let id):
                PhotoCrossfade(id: id)
                    .accessibilityElement()
                    .accessibilityLabel("Start and end position of \(exercise.name)")

            case nil:
                Group {
                    if store.catalogue.isEmpty {
                        DemoMessage(symbol: "play.rectangle", title: "Loading demos…", detail: store.catalogueError)
                    } else {
                        DemoMessage(symbol: "play.rectangle", title: "No demo for this exercise", action: ("Choose one", { choosing = true }))
                    }
                }
                .background(Theme.fill.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: stageHeight)
        .clipShape(.rect(cornerRadius: 16))
    }

    @ViewBuilder
    private func placeholder(_ file: String, media: ExerciseMedia) -> some View {
        if let failure = store.failures[file] {
            DemoMessage(
                symbol: "exclamationmark.triangle",
                title: "Couldn't load the demo",
                detail: failure,
                action: ("Try again", { store.retry(media, variant: variant) }),
                dark: false
            )
        } else {
            DemoLoading()
        }
    }
}

/// Spinner with a caption, the same on every demo stage.
struct DemoLoading: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Loading demo…").font(Typo.body(12.5)).foregroundStyle(Theme.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Empty or error state on a demo stage: an icon, a line, an optional detail and button.
struct DemoMessage: View {
    let symbol: String
    let title: String
    var detail: String?
    var action: (String, () -> Void)?
    /// false keeps fixed dark text, for stages that stay white in dark mode.
    var dark = true

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(dark ? Theme.ink3 : Color(white: 0.55))
            Text(title)
                .font(Typo.body(15, .semibold))
                .foregroundStyle(dark ? Theme.ink : Color(white: 0.1))
            if let detail {
                Text(detail)
                    .font(Typo.body(12.5))
                    .foregroundStyle(dark ? Theme.ink3 : Color(white: 0.45))
                    .lineLimit(3)
            }
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.smallPrimary)
                    .padding(.top, 4)
            }
        }
        .multilineTextAlignment(.center)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A still of the exercise's demo for list rows on wide screens: the figure's start and end
/// position, the first photo, or the first frame of the drawing.
struct ExerciseDemoThumbnail: View {
    let exercise: ExerciseDef
    var size: CGFloat = 56

    private var store: ExerciseMediaStore { .shared }

    var body: some View {
        Group {
            switch store.media(for: exercise) {
            case .figure(let move, let load):
                MotionFigureView(move: move, load: load, primary: Set(exercise.primary), secondary: Set(exercise.secondary), animated: false)
                    .padding(size * 0.06)
                    .background(Theme.fill)
            case .some(let media):
                ExerciseAnimation(media: media, animated: false) { Color.white }
                    .padding(size * 0.04)
                    .background(.white)
            case nil:
                Image(systemName: "play.rectangle")
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.fill)
            }
        }
        .frame(width: size * 1.25, height: size)
        .clipShape(.rect(cornerRadius: size * 0.24))
        .accessibilityHidden(true)
    }
}

/// The start and end photos fading into each other, holding on each, with a Start / End label.
/// Fills the stage it's given; the photos are fitted on white so nothing is cut off.
struct PhotoCrossfade: View {
    let id: String
    @State private var frames: [UIImage] = []
    @State private var failed = false
    @State private var attempt = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let duration = 3.2

    var body: some View {
        ZStack {
            Color.white
            if frames.count == 2 {
                if reduceMotion {
                    HStack(spacing: 6) {
                        ForEach(0..<2, id: \.self) { Image(uiImage: frames[$0]).resizable().scaledToFit() }
                    }
                } else {
                    TimelineView(.animation) { context in
                        let phase = MotionPattern.phase(at: context.date.timeIntervalSinceReferenceDate, duration: Self.duration)
                        // Hold on each photo, fade in the middle.
                        let fade = min(max((phase - 0.3) / 0.4, 0), 1)
                        ZStack {
                            Image(uiImage: frames[0]).resizable().scaledToFit()
                            Image(uiImage: frames[1]).resizable().scaledToFit().opacity(fade)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .topLeading) {
                            Text(fade < 0.5 ? "Start" : "End")
                                .font(Typo.body(12, .semibold))
                                .foregroundStyle(Color(white: 0.1))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(white: 0.94), in: .capsule)
                                .padding(10)
                        }
                    }
                }
            } else if failed {
                DemoMessage(
                    symbol: "wifi.exclamationmark",
                    title: "Couldn't load the photos",
                    detail: "They download once, then stay on this iPhone.",
                    action: ("Try again", {
                        ExerciseMediaStore.shared.retry(.photos(id: id))
                        attempt += 1
                    }),
                    dark: false
                )
            } else {
                DemoLoading().environment(\.colorScheme, .light)
            }
        }
        .task(id: "\(id)-\(attempt)") {
            failed = false
            guard let data = await ExerciseMediaStore.shared.photos(id) else {
                failed = true
                return
            }
            let images = await Task.detached(priority: .userInitiated) {
                data.compactMap { UIImage(data: $0)?.preparingForDisplay() }
            }.value
            frames = images
            failed = images.count < 2
        }
    }
}

/// Live workout: the animation in a sheet, opened from the exercise badge.
struct ExerciseDemoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: ExerciseDef

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ExerciseDemoCard(exercise: exercise, height: 340)
                    MuscleTargetsCard(exercise: exercise).card()
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Pick which Workout API exercise to show, when the automatic name match is wrong or missing.
struct AnimationChooser: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: ExerciseDef
    @State private var search = ""

    private var media: ExerciseMediaStore { .shared }

    var body: some View {
        let current = media.code(for: exercise)
        NavigationStack {
            List {
                Section {
                    Button {
                        media.choose(nil, for: exercise); dismiss()
                    } label: {
                        row("Automatic", detail: "Match by name", selected: media.isAutomatic(exercise))
                    }
                    Button {
                        media.choose("", for: exercise); dismiss()
                    } label: {
                        row("No animation", detail: nil, selected: !media.isAutomatic(exercise) && current == nil)
                    }
                }
                Section {
                    let results = search.isEmpty
                        ? WorkoutAPIMatcher.suggestions(for: exercise.name, in: media.catalogue)
                        : WorkoutAPIMatcher.search(search, in: media.catalogue)
                    ForEach(results) { item in
                        Button {
                            media.choose(item.code, for: exercise); dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ExerciseAnimation(media: .workoutAPI(code: item.code), animated: false) { Theme.fill }
                                    .frame(width: 44, height: 44)
                                    .background(.white, in: .rect(cornerRadius: 10))
                                row(item.name, detail: nil, selected: !media.isAutomatic(exercise) && current == item.code)
                            }
                        }
                    }
                } header: {
                    Text(search.isEmpty ? "Closest names" : "Workout API").eyebrow(11)
                }
            }
            .buttonStyle(.plain)
            .screenBackground()
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search \(media.catalogue.count) exercises")
            .navigationTitle("Animation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private func row(_ title: String, detail: String?, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.body(15, .semibold)).foregroundStyle(Theme.ink)
                if let detail { Text(detail).font(Typo.body(12.5)).foregroundStyle(Theme.ink3) }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
            }
        }
        .contentShape(.rect)
    }
}

/// Workout API key and cache in Settings.
struct ExerciseMediaSettingsSection: View {
    @State private var key = ""
    @State private var error: String?
    @State private var saving = false
    @State private var cacheBytes = 0

    private var media: ExerciseMediaStore { .shared }

    var body: some View {
        @Bindable var media = media

        VStack(alignment: .leading, spacing: 12) {
            Text("Exercise demos").eyebrow(11.5)
            VStack(spacing: 0) {
                ForEach(Array(ExerciseDemoStyle.allCases.enumerated()), id: \.element) { index, style in
                    if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                    Button {
                        media.style = style
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.label).font(Typo.body(15, .semibold)).foregroundStyle(Theme.ink)
                                Text(style.detail).font(Typo.body(12.5)).foregroundStyle(Theme.ink3)
                            }
                            Spacer()
                            if media.style == style {
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(14)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .card(padding: 0, cornerRadius: 18)

            Text("Workout API").eyebrow(11.5).padding(.top, 6)
            if media.hasKey {
                VStack(spacing: 0) {
                    HStack {
                        Label("Workout API key saved", systemImage: "key.fill").font(Typo.body(15, .semibold))
                        Spacer()
                        Button("Remove", role: .destructive) { media.removeKey() }
                            .font(Typo.body(14, .semibold))
                    }
                    .padding(14)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    Toggle("Use as exercise icons", isOn: $media.showsThumbnails)
                        .font(Typo.body(15, .semibold))
                        .padding(14)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    HStack {
                        Text("Saved on this iPhone").font(Typo.body(15, .semibold))
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file))
                            .font(Typo.body(14))
                            .foregroundStyle(Theme.ink3)
                        Button("Clear") { media.clearCache(); cacheBytes = media.cacheBytes }
                            .font(Typo.body(14, .semibold))
                            .disabled(cacheBytes == 0)
                    }
                    .padding(14)
                }
                .card(padding: 0, cornerRadius: 18)
                Text("Drawings come from Workout API (\(media.catalogue.count) exercises). Each one is downloaded the first time you open it and then kept on this iPhone.")
                    .font(Typo.body(12.5))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connect Workout API").font(Typo.body(15, .semibold))
                    Text("Optional. A Workout API key adds their animated line drawings as a third style. Your key stays in this iPhone's Keychain.")
                        .font(Typo.body(13))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        SecureField("Paste key", text: $key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(Typo.body(15))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(Theme.fill, in: .rect(cornerRadius: 12))
                        Button(saving ? "Checking…" : "Save") {
                            saving = true
                            Task {
                                error = await media.setKey(key)
                                if error == nil { key = "" }
                                saving = false
                            }
                        }
                        .buttonStyle(.smallPrimary)
                        .disabled(saving || key.trimmingCharacters(in: .whitespaces).count < 10)
                    }
                    if let error {
                        Text(error)
                            .font(Typo.body(12.5, .semibold))
                            .foregroundStyle(Theme.danger)
                    }
                    Link("Get a key at workoutapi.com", destination: WorkoutAPI.signUpURL)
                        .font(Typo.body(13, .semibold))
                }
                .card(padding: 14, cornerRadius: 20)
            }
        }
        .onAppear { cacheBytes = media.cacheBytes }
    }
}
