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
    private let bundleIdentifier = "software.micropixels.BatFi"
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
        } catch let error as NSError {
            logger.error("Error renaming downloaded file: \(error.localizedDescription)")
            updateInstallationState(.movingError(error as NSError))
            return nil
        }
    }

    func unzipFile(at sourceURL: URL) -> Bool {
        updateInstallationState(.unzipping)
        if let runningInstance =  NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            logger.notice("App is running")
            if !runningInstance.terminate() {
                runningInstance.forceTerminate()
                logger.notice("App force terminated")
            }
        }
        let process = Process()
        process.launchPath = "/usr/bin/unzip"
        process.arguments = ["-o", sourceURL.path, "-d", "/Applications", "-x", "__MACOSX*"]

        do {
            try process.run()
            process.waitUntilExit()
            updateInstallationState(.done)
            return true
        } catch {
            logger.error("Error unzipping file: \(error.localizedDescription)")
            updateInstallationState(.unzippingError(error as NSError))
            return false
        }
    }

    private func clearQuarantineAttributes() {
        let process = Process()
        process.launchPath = "/usr/bin/xattr"
        process.arguments = ["-dr", "com.apple.quarantine", installedAppPath]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("Error clearing quarantine attributes: \(error.localizedDescription)")
        }
    }

    private func cleanUp(url: URL) {
        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(at: url)
        } catch {
            logger.error("Error cleaning up: \(error.localizedDescription)")
        }
    }

    private func findAndOpenApp(_ handler: @escaping () -> Void)  {
        logger.debug("Finish and open app")
        let url = URL(filePath: installedAppPath)
        logger.debug("opening app at \(url.absoluteString)")
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in
            DispatchQueue.main.async {
                handler()
            }
        }
    }

    private func resetDefaults() {
        let process = Process()
        process.launchPath = "/usr/bin/defaults"
        process.arguments = ["delete", bundleIdentifier]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("Error deleting defaults: \(error.localizedDescription)")
        }
    }

    private func downloadFile() {
        updateInstallationState(.downloading(progress: 0))

        let session = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: nil)
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        logger.debug("Downloading app from \(url.absoluteString)")
        let task = session.downloadTask(with: request)
        task.resume()
    }

    // MARK: URLSessionDownloadDelegate Methods
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse else {
            updateInstallationState(.downloadError(
                NSError(domain: "Installer", code: 0, userInfo: [NSLocalizedDescriptionKey: "No response"])
            ))
            return
        }
        guard response.statusCode == 200 else {
            updateInstallationState(.downloadError(
                NSError(domain: "Installer", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: "Bad status code"])
            ))
            return
        }
        guard let tempLocation = renameDownloadedFile(downloadTask.response?.suggestedFilename, location: location) else {
            return
        }
        // unzip it
        guard unzipFile(at: tempLocation) else { return }
        clearQuarantineAttributes()
        cleanUp(url: tempLocation)
        resetDefaults()
        findAndOpenApp { [weak self] in
            self?.updateInstallationState(.done)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
                NSApp.terminate(nil)
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        logger.notice("\(#function)")
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        logger.notice("Download progress: \(progress), totalbytes: \(totalBytesWritten), expected: \(totalBytesExpectedToWrite)")
        updateInstallationState(.downloading(progress: progress))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        logger.notice("\(#function)")
        if let error = error {
            logger.error("Download error: \(error.localizedDescription)")
            updateInstallationState(.downloadError(error as NSError))
        }
    }

    func updateInstallationState(_ state: InstallationState) {
        Task { @MainActor in
            logger.notice("Installation state: \(state, privacy: .public)")
            installationState = state
        }
    }
}
