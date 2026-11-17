import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var iCloudBridge: RiffShelfICloudBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "com.sonniersolution.riffshelf/icloud",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    let bridge = RiffShelfICloudBridge()
    iCloudBridge = bridge
    channel.setMethodCallHandler { [weak bridge] call, result in
      bridge?.handle(call, result: result)
    }
  }
}

/// The public iCloud Documents directory is visible in the Files app as RiffShelf.
/// Only file names and file bytes are sent to Flutter; the server is not involved.
private final class RiffShelfICloudBridge: NSObject {
  private let supported = Set(["txt", "gp3", "gp4", "gp5", "gpx"])
  private let maxFileBytes = 20 * 1024 * 1024
  private var documentsURL: URL?
  private var query: NSMetadataQuery?
  private var observer: NSObjectProtocol?
  private var pending: FlutterResult?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "list":
      list(result)
    case "read":
      guard let args = call.arguments as? [String: String],
            let path = args["path"] else {
        result(FlutterError(code: "invalid_path", message: "Missing file path.", details: nil))
        return
      }
      read(path, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func list(_ result: @escaping FlutterResult) {
    guard query == nil else {
      result(FlutterError(code: "busy", message: "iCloud scan already running.", details: nil))
      return
    }
    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let root = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "icloud_unavailable",
            message: "Enable iCloud Drive for RiffShelf to import automatically.", details: nil))
        }
        return
      }
      let documents = root.appendingPathComponent("Documents", isDirectory: true)
      do {
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "icloud_unavailable", message: error.localizedDescription, details: nil))
        }
        return
      }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.documentsURL = documents.standardizedFileURL
        self.pending = result
        let scan = NSMetadataQuery()
        scan.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        scan.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        self.query = scan
        self.observer = NotificationCenter.default.addObserver(
          forName: .NSMetadataQueryDidFinishGathering,
          object: scan, queue: .main
        ) { [weak self] _ in
          self?.finishScan()
        }
        if !scan.start() {
          self.finishScan(error: "Could not search iCloud Drive.")
        }
        // The query may not finish while iCloud is temporarily unavailable.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self, weak scan] in
          guard let self, let scan, self.query === scan else { return }
          self.finishScan(error: "iCloud search timed out; try Sync now.")
        }
      }
    }
  }

  private func finishScan(error: String? = nil) {
    guard let scan = query, let completion = pending else { return }
    scan.disableUpdates()
    let entries: [[String: String]] = scan.results.compactMap { entry in
      guard let item = entry as? NSMetadataItem,
            let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
            supported.contains(url.pathExtension.lowercased()),
            let root = documentsURL,
            url.standardizedFileURL.path.hasPrefix(root.path + "/") else { return nil }
      return ["name": url.lastPathComponent, "path": url.path]
    }
    scan.stop()
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
    query = nil
    pending = nil
    if let error {
      completion(FlutterError(code: "scan_failed", message: error, details: nil))
    } else {
      completion(entries)
    }
  }

  private func read(_ path: String, result: @escaping FlutterResult) {
    guard let root = documentsURL else {
      result(FlutterError(code: "icloud_unavailable", message: "Scan iCloud first.", details: nil))
      return
    }
    let url = URL(fileURLWithPath: path).standardizedFileURL
    guard url.path.hasPrefix(root.path + "/"),
          supported.contains(url.pathExtension.lowercased()) else {
      result(FlutterError(code: "invalid_path", message: "File is outside RiffShelf.", details: nil))
      return
    }
    DispatchQueue.global(qos: .utility).async {
      do {
        let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .fileSizeKey])
        if let length = values.fileSize, length > self.maxFileBytes {
          throw NSError(domain: "RiffShelf", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Tab exceeds the 20 MB import limit."
          ])
        }
        if values.ubiquitousItemDownloadingStatus != .current {
          try FileManager.default.startDownloadingUbiquitousItem(at: url)
          DispatchQueue.main.async {
            result(FlutterError(code: "pending", message: "Downloading tab from iCloud.", details: nil))
          }
          return
        }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var fileBytes: Data?
        var readError: Error?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { safeURL in
          do {
            fileBytes = try Data(contentsOf: safeURL, options: .mappedIfSafe)
          } catch {
            readError = error
          }
        }
        if let error = coordinationError ?? (readError as NSError?) { throw error }
        guard let data = fileBytes else {
          throw NSError(domain: "RiffShelf", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Could not read tab file."
          ])
        }
        guard data.count <= self.maxFileBytes else {
          throw NSError(domain: "RiffShelf", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Tab exceeds the 20 MB import limit."
          ])
        }
        DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: data)) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "read_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}
