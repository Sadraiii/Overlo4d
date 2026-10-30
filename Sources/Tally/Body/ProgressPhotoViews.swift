import PhotosUI
import SwiftUI
// SwiftUI's PhotosPicker lives in this cross-import overlay; Xcode adds it automatically, SwiftPM on Linux doesn't.
import _PhotosUI_SwiftUI
import TallyCore
import TallyKit
import UIKit

struct PhotoDayRoute: Hashable {
    let day: DayKey
}

/// Progress photos on the Body screen: a strip of photo days and the Compare button.
struct PhotosCard: View {
    @Environment(BodyStore.self) private var store
    let onAdd: () -> Void
    let onCompare: () -> Void

    var body: some View {
        let days = store.log.photoDays
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Progress photos").eyebrow()
                Spacer()
                Button("Add", systemImage: "camera", action: onAdd)
                    .font(Typo.body(13, .semibold))
                    .labelStyle(.titleAndIcon)
            }

            if days.isEmpty {
                Text("Take a front, side and back photo every 2–4 weeks, same spot, same light, same time of day. Photos stay on this phone.")
                    .font(Typo.body(13.5))
                    .foregroundStyle(Theme.ink3)
                Button("Take first photos", action: onAdd)
                    .buttonStyle(.bigPrimary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(days, id: \.self) { day in
                            NavigationLink(value: PhotoDayRoute(day: day)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    PhotoThumb(photo: store.log.photos(on: day).first)
                                        .frame(width: 84, height: 112)
                                    Text(day.date().formatted(.dateTime.day().month(.abbreviated)))
                                        .font(Typo.body(12, .semibold))
                                        .foregroundStyle(Theme.ink2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollClipDisabled()

                if days.count >= 2 {
                    Button(action: onCompare) {
                        Label("Compare before and after", systemImage: "rectangle.split.2x1")
                    }
                    .buttonStyle(.bigPrimary)
                } else {
                    Text("Add photos on another day to compare them side by side.")
                        .font(Typo.body(13))
                        .foregroundStyle(Theme.ink3)
                }
            }
        }
        .card(padding: 14)
    }
}

/// A cached thumbnail, or a placeholder.
struct PhotoThumb: View {
    @Environment(BodyStore.self) private var store
    let photo: ProgressPhoto?

    var body: some View {
        Group {
            if let photo, let image = store.thumbnail(photo) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.rectangle")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.ink3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.paper)
            }
        }
        .clipShape(.rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// Takes or picks a front, side and back photo for a day. The last photo of each pose is shown to line up with.
struct AddPhotosSheet: View {
    @Environment(BodyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now

    private var day: DayKey { DayKey(date) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                        .font(Typo.body(15))
                        .card(padding: 12, cornerRadius: 20)

                    ForEach(PhotoPose.allCases) { pose in
                        PoseSlot(pose: pose, day: day)
                    }

                    Text("Tips: phone at chest height on a shelf or tripod, a plain wall, the same lighting every time. Relaxed and flexed, but always the same. Photos are kept in the app only, not in your photo library.")
                        .font(Typo.body(12.5))
                        .foregroundStyle(Theme.ink3)
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Progress photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// One pose: this day's photo (or the last one, faded, as a guide) with camera and library buttons.
private struct PoseSlot: View {
    @Environment(BodyStore.self) private var store
    let pose: PhotoPose
    let day: DayKey

    @State private var item: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var failed = false

    var body: some View {
        let current = store.log.photo(on: day, pose: pose)
        let previous = store.log.photos.last { $0.pose == pose && $0.day < day }

        HStack(alignment: .top, spacing: 12) {
            ZStack {
                if let current {
                    PhotoThumb(photo: current)
                } else if let previous {
                    PhotoThumb(photo: previous).opacity(0.35)
                    Text("Last time").font(Typo.body(11, .bold)).foregroundStyle(Theme.ink)
                } else {
                    PhotoThumb(photo: nil)
                }
            }
            .frame(width: 90, height: 120)

            VStack(alignment: .leading, spacing: 8) {
                Text(pose.name).display(22)
                if let current {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(Typo.body(13, .semibold))
                        .foregroundStyle(Theme.good)
                    Button("Delete", systemImage: "trash", role: .destructive) { store.deletePhoto(current.id) }
                        .font(Typo.body(13, .semibold))
                } else {
                    HStack(spacing: 8) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Camera", systemImage: "camera") { showingCamera = true }
                                .buttonStyle(.bordered)
                        }
                        PhotosPicker(selection: $item, matching: .images) {
                            Label("Library", systemImage: "photo")
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(Typo.body(13, .semibold))
                }
                if failed {
                    Text("Couldn't save that photo.").font(Typo.body(12)).foregroundStyle(Theme.danger)
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 12, cornerRadius: 20)
        .onChange(of: item) {
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    failed = !store.addPhoto(image, pose: pose, on: day)
                } else {
                    failed = true
                }
                self.item = nil
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(
                onPick: { failed = !store.addPhoto($0, pose: pose, on: day) },
                onClose: { showingCamera = false }
            )
            .ignoresSafeArea()
        }
    }
}

/// The system camera. Calls `onPick` with the photo, then `onClose` (also on cancel).
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPick(image) }
            parent.onClose()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onClose()
        }
    }
}

/// A day's photos full size, with that day's measurements.
struct PhotoDayView: View {
    @Environment(BodyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: DayKey

    @State private var deleting: ProgressPhoto?

    var body: some View {
        let photos = store.log.photos(on: day)
        let entry = store.entry(on: day)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(photos) { photo in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(photo.pose.name).display(22)
                            Spacer()
                            if let image = store.image(photo) {
                                ShareLink(item: Image(uiImage: image), preview: SharePreview("\(photo.pose.name), \(BodyFormat.day(day))", image: Image(uiImage: image))) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = photo }
                                .labelStyle(.iconOnly)
                                .padding(.leading, 12)
                        }
                        .font(.system(size: 16, weight: .semibold))
                        if let image = store.image(photo) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(.rect(cornerRadius: 16))
                        }
                    }
                }

                if let entry, !entry.values.isEmpty {
                    BodyEntryRow(entry: entry).card(padding: 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle(BodyFormat.day(day))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this photo?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let deleting else { return }
                store.deletePhoto(deleting.id)
                self.deleting = nil
                if store.log.photos(on: day).isEmpty { dismiss() }
            }
        }
    }
}

/// Before and after: two days of the same pose side by side or under a slider, with what changed in between.
struct CompareView: View {
    @Environment(BodyStore.self) private var store
    @Environment(FoodStore.self) private var food

    enum Mode: String, CaseIterable, Identifiable {
        case sideBySide = "Side by side"
        case slider = "Slider"
        var id: String { rawValue }
    }

    @State private var pose = PhotoPose.front
    @State private var from: DayKey?
    @State private var to: DayKey?
    @State private var mode = Mode.sideBySide
    @State private var split: CGFloat = 0.5
    @State private var shareImage: Image?

    var body: some View {
        let days = store.log.days(with: pose)
        let before = from.flatMap { store.log.photo(on: $0, pose: pose) }
        let after = to.flatMap { store.log.photo(on: $0, pose: pose) }

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Pose", selection: $pose) {
                    ForEach(PhotoPose.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)

                if days.count < 2 {
                    Text("You need \(pose.name.lowercased()) photos on two different days to compare.")
                        .font(Typo.body(14))
                        .foregroundStyle(Theme.ink3)
                        .card(padding: 14)
                } else {
                    HStack(spacing: 8) {
                        dayMenu("Before", selection: $from, days: days)
                        dayMenu("After", selection: $to, days: days)
                    }

                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let before, let after, let from, let to {
                        Group {
                            switch mode {
                            case .sideBySide: SideBySide(before: before, after: after, from: from, to: to)
                            case .slider: SliderCompare(before: before, after: after, split: $split)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Text(BodyFormat.apart(from, to))
                            .font(Typo.body(13, .semibold))
                            .foregroundStyle(Theme.ink2)
                            .frame(maxWidth: .infinity)

                        ChangesCard(changes: BodyLog.changes(from: min(from, to), to: max(from, to), entries: store.entries, weights: food.weights))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let shareImage {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: shareImage, preview: SharePreview("Progress", image: shareImage))
                }
            }
        }
        .onAppear {
            pose = store.log.bestComparisonPose
            pickDefaults()
        }
        .onChange(of: pose) { pickDefaults() }
        .task(id: [from?.rawValue, to?.rawValue, pose.rawValue]) { renderShareImage() }
    }

    private func pickDefaults() {
        let days = store.log.days(with: pose)
        if let from, days.contains(from), let to, days.contains(to), from != to { return }
        let pair = store.log.defaultComparison(pose)
        from = pair?.from
        to = pair?.to
    }

    private func dayMenu(_ title: String, selection: Binding<DayKey?>, days: [DayKey]) -> some View {
        Menu {
            Picker(title, selection: selection) {
                ForEach(days.reversed(), id: \.self) { Text(BodyFormat.day($0)).tag(Optional($0)) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).eyebrow(10)
                HStack {
                    Text(selection.wrappedValue.map(BodyFormat.day) ?? "Pick a day")
                        .font(Typo.body(14, .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ink3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 10, cornerRadius: 20)
        }
    }

    /// The side-by-side picture with dates, for sharing.
    private func renderShareImage() {
        guard let from, let to, let before = store.log.photo(on: from, pose: pose), let after = store.log.photo(on: to, pose: pose),
              let beforeImage = store.image(before), let afterImage = store.image(after)
        else { shareImage = nil; return }
        let card = CompareShareCard(before: beforeImage, after: afterImage, from: from, to: to)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        shareImage = renderer.uiImage.map { Image(uiImage: $0) }
    }
}

private struct SideBySide: View {
    @Environment(BodyStore.self) private var store
    let before: ProgressPhoto
    let after: ProgressPhoto
    let from: DayKey
    let to: DayKey

    var body: some View {
        HStack(spacing: 6) {
            half(before, label: BodyFormat.day(from))
            half(after, label: BodyFormat.day(to))
        }
    }

    private func half(_ photo: ProgressPhoto, label: String) -> some View {
        VStack(spacing: 6) {
            Color.clear
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay {
                    if let image = store.image(photo) {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                }
                .clipShape(.rect(cornerRadius: 14))
            Text(label).font(Typo.body(12, .semibold)).foregroundStyle(Theme.ink2)
        }
    }
}

/// After underneath, before on top up to the handle. Drag to wipe between them.
private struct SliderCompare: View {
    @Environment(BodyStore.self) private var store
    let before: ProgressPhoto
    let after: ProgressPhoto
    @Binding var split: CGFloat

    var body: some View {
        Color.clear
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .leading) {
                        photo(after, size: proxy.size)
                        photo(before, size: proxy.size)
                            .mask(alignment: .leading) { Rectangle().frame(width: width * split) }
                        Rectangle()
                            .fill(.white)
                            .frame(width: 2)
                            .shadow(radius: 2)
                            .overlay {
                                Image(systemName: "arrow.left.and.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Theme.ink)
                                    .frame(width: 34, height: 34)
                                    .background(.white, in: .circle)
                                    .shadow(radius: 3)
                            }
                            .offset(x: width * split - 1)
                        HStack {
                            tag("Before")
                            Spacer()
                            tag("After")
                        }
                        .padding(10)
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .contentShape(.rect)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        split = min(max(value.location.x / max(width, 1), 0), 1)
                    })
                }
            }
            .clipShape(.rect(cornerRadius: 14))
            .sensoryFeedback(.selection, trigger: split == 0 || split == 1)
    }

    private func photo(_ photo: ProgressPhoto, size: CGSize) -> some View {
        Group {
            if let image = store.image(photo) {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(Typo.body(11, .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.45), in: .capsule)
    }
}

/// Weight and measurements on the before and after days.
private struct ChangesCard: View {
    let changes: [BodyChange]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What changed").eyebrow()
            if changes.isEmpty {
                Text("Log weight or measurements within two weeks of both photo days to see what changed.")
                    .font(Typo.body(13))
                    .foregroundStyle(Theme.ink3)
            } else {
                ForEach(changes) { change in
                    HStack {
                        Text(change.name).font(Typo.body(14)).foregroundStyle(Theme.ink2)
                        Spacer()
                        Text("\(BodyFormat.number(change.from)) → \(BodyFormat.number(change.to))")
                            .font(Typo.body(13))
                            .foregroundStyle(Theme.ink3)
                            .monospacedDigit()
                        Text("\(BodyFormat.signed(change.delta)) \(change.unit)")
                            .font(Typo.body(14, .semibold))
                            .foregroundStyle(BodyFormat.color(change.isProgress))
                            .monospacedDigit()
                            .frame(minWidth: 74, alignment: .trailing)
                    }
                }
            }
        }
        .card(padding: 14)
    }
}

/// The before/after picture that's shared: both photos with their dates and the app's seal.
private struct CompareShareCard: View {
    let before: UIImage
    let after: UIImage
    let from: DayKey
    let to: DayKey

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                half(before, label: BodyFormat.day(from))
                half(after, label: BodyFormat.day(to))
            }
            HStack {
                Seal(size: 26)
                Text("Overload").font(Typo.display(18)).tracking(1.2).textCase(.uppercase)
                Spacer()
                Text(BodyFormat.apart(from, to)).font(Typo.body(14, .semibold)).foregroundStyle(Theme.ink2)
            }
        }
        .padding(16)
        .frame(width: 640)
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
    }

    private func half(_ image: UIImage, label: String) -> some View {
        VStack(spacing: 6) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 300, height: 400)
                .clipShape(.rect(cornerRadius: 14))
            Text(label).font(Typo.body(14, .semibold))
        }
    }
}
