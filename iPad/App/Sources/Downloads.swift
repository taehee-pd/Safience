import UIKit
import WebKit

/// Files a page hands over: an export from Figma, an attachment from Slack.
/// Each is saved to a folder of the app's own, then the system's save sheet
/// asks where in Files it should go.
@MainActor
final class Downloads: NSObject, WKDownloadDelegate {
    static let shared = Downloads()

    private struct Running {
        weak var page: Page?
        var file: URL?
    }

    private var running: [ObjectIdentifier: Running] = [:]

    func adopt(_ download: WKDownload, for page: Page) {
        download.delegate = self
        running[ObjectIdentifier(download)] = Running(page: page, file: nil)
    }

    /// A page with a download going keeps its process (Page.mustStay).
    func isDownloading(for page: Page) -> Bool {
        running.values.contains { $0.page === page }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping @MainActor (URL?) -> Void) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            completionHandler(nil)
            return
        }
        // The page names the file; only its last part is used, so a name
        // with slashes can't reach outside the folder.
        var name = URL(fileURLWithPath: suggestedFilename).lastPathComponent
        if name.isEmpty || name == "/" || name == "." || name == ".." { name = "Download" }
        let file = folder.appendingPathComponent(name)
        running[ObjectIdentifier(download)]?.file = file
        completionHandler(file)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let done = running.removeValue(forKey: ObjectIdentifier(download)), let file = done.file,
              let presenter = done.page?.host?.presenter ?? Session.shared.allBrowsers.first(where: \.isConnected)?.presenter
        else { return }
        let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
        presenter.present(picker, animated: true)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let failed = running.removeValue(forKey: ObjectIdentifier(download)),
              let presenter = failed.page?.host?.presenter else { return }
        Dialogs.notice(title: "The download stopped", message: error.localizedDescription, on: presenter)
    }
}
