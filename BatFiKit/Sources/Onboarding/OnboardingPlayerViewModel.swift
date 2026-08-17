//
//  OnboardingPlayerViewModel.swift
//  NepTunes
//
//  Created by Adam Różyński on 16/07/2021.
//

import AVKit
import Combine
import Foundation

private extension OnboardingScreen {
    var fileName: String? {
        switch self {
        case .welcome:
            return nil
        case .helper:
            return "helper"
        case .charging:
            // Re-recorded for 4.0. The clip it replaces showed a three-tab Settings window
            // and a Charging pane several releases behind this one; the name is versioned
            // rather than overwritten so an older build keeps playing the video that matches
            // the app it is.
            return "usage_v4"
        case .license:
            return "license_v2"
        }
    }
}

class OnboardingPlayerViewModel: ObservableObject {
    private var currentPageCancellable: AnyCancellable?
    private var currentItemCancellable: AnyCancellable?

    private var currentItem: AVPlayerItem?
    private(set) lazy var player: AVPlayer = {
        let player = AVPlayer()
        player.volume = 0
        player.actionAtItemEnd = .none
        return player
    }()

    init(_ currentPage: AnyPublisher<OnboardingScreen, Never>) {
        currentPageCancellable = currentPage
            .sink { [weak self] currentPage in
                self?.updatePlayer(for: currentPage)
            }
    }

    private func updatePlayer(for screen: OnboardingScreen) {
        // Only the helper pane's clip, which is the one being re-recorded and the one the pane
        // stands a flat fill in for. Every other pane plays exactly what it ships with — one
        // player is shared between them, so skipping the fetch outright would leave the others
        // showing an empty player rather than their own video.
        guard !(OnboardingRecordingMode.isEnabled && screen == .helper) else {
            player.replaceCurrentItem(with: nil)
            return
        }
        updatePlayer(screen.fileName)
    }

    private func updatePlayer(_ filename: String?) {
        if let filename {
            let item = playerItemForVideoName(filename)
            player.replaceCurrentItem(with: item)
            setUpSubscribersForItem(item)
            player.play()
        } else {
            player.replaceCurrentItem(with: nil)
        }
    }

    private func setUpSubscribersForItem(_ item: AVPlayerItem) {
        currentItemCancellable?.cancel()
        currentItemCancellable = NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .map { $0.object as? AVPlayerItem }
            .sink {
                $0?.seek(to: CMTime.zero, completionHandler: nil)
            }
    }

    private func playerItemForVideoName(_ name: String) -> AVPlayerItem {
        let urlString = "https://files.micropixels.software/batfi/" + name + ".mp4"
        let url = URL(string: urlString)!
        let asset = AVURLAsset(url: url)
        return AVPlayerItem(asset: asset)
    }
}
