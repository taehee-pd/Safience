import AppKit
import PadCore
import SwiftUI

extension Downloads {
    func reveal(_ item: Item) {
        guard let file = item.file else { return }
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }
}

struct DownloadList: View {
    @ObservedObject private var downloads = Downloads.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                Button("Clear Finished Activity") { downloads.clearFinished() }.buttonStyle(.borderless)
            }
            if let problem = downloads.storageProblem {
                    Text(problem).foregroundStyle(.red)
                    Button("Retry Saved Activity") { downloads.retryStorage() }
                }
            if downloads.items.isEmpty { Text("Downloaded files and progress appear here.").foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(downloads.items) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.name).font(.headline).lineLimit(2)
                            Text("\(Session.shared.workspace.space(item.space)?.name ?? "Removed Space") · \(item.source?.host ?? "Download")")
                                .font(.caption).foregroundStyle(.secondary)
                            if item.phase == .downloading {
                                ProgressView(value: item.fraction).controlSize(.small).accessibilityLabel("Download progress")
                                Button("Cancel Download") { downloads.cancel(item) }
                            } else if item.finished {
                                Button("Show in Finder") { downloads.reveal(item) }
                            } else {
                                Text(item.problem ?? "The download stopped.").font(.callout).foregroundStyle(.secondary)
                                if item.canResume || item.canRestart {
                                    Button(item.canResume ? "Resume" : "Try Again") { downloads.retry(item) }
                                } else {
                                    Text("Return to the source page in the named space to try again.").font(.caption)
                                }
                            }
                        }
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 420)
            Text("Clearing activity keeps downloaded files.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 340)
    }
}
