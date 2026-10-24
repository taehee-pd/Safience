import PadCore
import SwiftUI
import UIKit

extension Downloads {
    func present(on presenter: UIViewController?) {
        guard var owner = presenter else { return }
        while let presented = owner.presentedViewController, !presented.isBeingDismissed { owner = presented }
        let controller = UIHostingController(rootView: DownloadActivityView())
        controller.modalPresentationStyle = .formSheet
        owner.present(controller, animated: true)
    }
}

struct DownloadActivityButton: View {
    @ObservedObject private var downloads = Downloads.shared
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: downloads.active ? "arrow.down.circle.fill" : "arrow.down.circle")
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if downloads.activeCount > 0 {
                        Text("\(downloads.activeCount)").font(.caption2.bold()).padding(3)
                            .background(.regularMaterial, in: Capsule())
                    }
                }
        }
        .accessibilityLabel("Downloads, \(downloads.activeCount) active")
        .accessibilityHint("Shows progress, cancellation, saved files, and retry options")
    }
}

private struct DownloadActivityView: View {
    @ObservedObject private var downloads = Downloads.shared
    @Environment(\.dismiss) private var dismiss
    @State private var exporting: DownloadRecord?
    var body: some View {
        NavigationStack {
            List {
                if let problem = downloads.storageProblem {
                    Text(problem).foregroundStyle(.red)
                    Button("Retry Saved Activity") { downloads.retryStorage() }
                }
                if downloads.items.isEmpty { Text("Downloaded files and their progress appear here.").foregroundStyle(.secondary) }
                ForEach(downloads.items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.name).font(.headline)
                        Text("\(Session.shared.workspace.space(item.space)?.name ?? "Removed Space") · \(item.source?.host ?? "Download")")
                            .font(.caption).foregroundStyle(.secondary)
                        if item.phase == .downloading {
                            ProgressView(value: item.fraction).accessibilityLabel("Download progress")
                            Button("Cancel Download", role: .cancel) { downloads.cancel(item) }
                        } else if item.finished {
                            Text(item.exported ? "A copy was saved. The downloaded file is still available here." : "Downloaded. Save a copy to Files when you are ready.")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("Save to Files…") { exporting = item }
                        } else {
                            Text(item.problem ?? "The download stopped.").font(.callout).foregroundStyle(.secondary)
                            if item.canResume || item.canRestart {
                                Button(item.canResume ? "Resume" : "Try Again") { downloads.retry(item) }
                            } else {
                                Text("Return to its source page in the named space to start the download again.").font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if !downloads.items.isEmpty {
                    Button("Clear Finished Activity") { downloads.clearFinished() }
                    Text("Files not yet saved to Files remain in this list. Clearing activity does not delete files.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Downloads")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $exporting) { item in
                if let file = item.file { DownloadExporter(file: file, item: item.id) }
            }
        }
    }
}

private struct DownloadExporter: UIViewControllerRepresentable {
    let file: URL
    let item: UUID
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(item: item, close: { dismiss() }) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let item: UUID
        let close: () -> Void
        init(item: UUID, close: @escaping () -> Void) { self.item = item; self.close = close }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { close() }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if !urls.isEmpty { Downloads.shared.exported(item) }
            close()
        }
    }
}
