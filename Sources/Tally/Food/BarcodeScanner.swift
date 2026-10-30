import SwiftUI
import TallyKit
import VisionKit

/// Camera barcode scanner, with typing the number as a fallback.
struct BarcodeScannerSheet: View {
    let onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var scanned = false

    private var canScan: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if canScan {
                    BarcodeScannerView { code in
                        guard !scanned else { return }
                        scanned = true
                        onScan(code)
                    }
                    .ignoresSafeArea()
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.white.opacity(0.85), lineWidth: 3)
                        .frame(width: 280, height: 150)
                        .allowsHitTesting(false)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "camera.fill").font(.system(size: 32))
                        Text("Camera not available")
                            .font(Typo.body(16, .semibold))
                        Text("Allow camera access in Settings › Overlo4d, or type the number under the barcode.")
                            .font(Typo.body(14))
                            .multilineTextAlignment(.center)
                            .opacity(0.7)
                    }
                    .foregroundStyle(.white)
                    .padding(32)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    TextField("Or type the barcode", text: $typed)
                        .keyboardType(.numberPad)
                        .font(Typo.body(16))
                        .monospacedDigit()
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Theme.card, in: .rect(cornerRadius: 12))
                    Button("Look up") { onScan(typed) }
                        .buttonStyle(.smallPrimary)
                        .disabled(typed.filter(\.isNumber).count < 8)
                }
                .padding(16)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }
}

/// VisionKit's live scanner, reporting the first food barcode it sees.
private struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onScan(payload)
                    return
                }
            }
        }
    }
}
