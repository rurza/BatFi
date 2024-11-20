//
//  AppInstaller.swift
//  Installer
//
//  Created by Adam Różyński on 30/03/2024.
//

import AppKit
import os

final class AppInstaller: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @MainActor @Published
    var installationState: InstallationState = .initial

    private let appBundleName = "BatFi.app"
    private lazy var installedAppPath = "/Applications/\(appBundleName)"
    private lazy var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "App Installer")

    override init() {
        super.init()
    }

    @MainActor
    init(installationState: InstallationState) {
        self.installationState = installationState
        super.init()
    }

    func downloadAndInstallApp() {
        downloadFile()
    }

    private func renameDownloadedFile(_ suggestedFilename: String?, location: URL) -> URL? {
        do {
            let fileManager = FileManager.default
            let fileName = suggestedFilename ?? "BatFi.zip"
            let newLocation = location.deletingLastPathComponent().appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: newLocation.path) {
                try fileManager.removeItem(at: newLocation)
            }
            try fileManager.moveItem(at: location, to: newLocation)
            return newLocation
        } catch {
            logger.error("Error renaming downloaded file: \(error.localizedDescription)")
            updateInstallationState(.movingError(error as NSError))
            return nil
        }
    }

    func unzipFile(at sourceURL: URL) -> URL? {
        updateInstallationState(.unzipping)
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("UnzippedApp")
        do {
            if FileManager.default.fileExists(atPath: tempDirectory.path) {
                try FileManager.default.removeItem(at: tempDirectory)
            }
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", sourceURL.path, "-d", tempDirectory.path]
            try process.run()
            process.waitUntilExit()

            let unzippedAppPath = tempDirectory.appendingPathComponent(appBundleName)
            if FileManager.default.fileExists(atPath: unzippedAppPath.path) {
                return unzippedAppPath
            } else {
                logger.error("Unzipped file not found at expected location")
                updateInstallationState(.unzippingError(NSError(domain: "Installer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unzipped file not found"])))
                return nil
            }
        } catch {
            logger.error("Error unzipping file: \(error.localizedDescription)")
            updateInstallationState(.unzippingError(error as NSError))
            return nil
        }
    }

    private func moveApp(to destination: URL, from source: URL) {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: source, to: destination)
            updateInstallationState(.done)
            NSWorkspace.shared.openApplication(at: destination, configuration: .init()) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                    NSApp.terminate(nil)
                }
            }
        } catch {
            logger.error("Error moving app: \(error.localizedDescription)")
            updateInstallationState(.movingError(error as NSError))
        }
    }

    private func clearQuarantineAttributes(for path: String) {
        let process = Process()
        process.launchPath = "/usr/bin/xattr"
        process.arguments = ["-dr", "com.apple.quarantine", path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("Error clearing quarantine attributes: \(error.localizedDescription)")
        }
    }

    private func downloadFile() {
        updateInstallationState(.downloading(progress: 0))

        let session = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: nil)
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 130)
        logger.debug("Downloading app")
        let task = session.downloadTask(with: request)
        task.resume()
    }

    // MARK: URLSessionDownloadDelegate Methods
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let tempLocation = renameDownloadedFile(downloadTask.response?.suggestedFilename, location: location) else {
            return
        }
        guard let unzippedAppPath = unzipFile(at: tempLocation) else { return }
        clearQuarantineAttributes(for: unzippedAppPath.path)
        moveApp(to: URL(fileURLWithPath: installedAppPath), from: unzippedAppPath)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        updateInstallationState(.downloading(progress: progress))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            logger.error("Download error: \(error.localizedDescription)")
            updateInstallationState(.downloadError(error as NSError))
        }
    }

    private func updateInstallationState(_ state: InstallationState) {
        DispatchQueue.main.async {
            self.installationState = state
        }
    }
}
