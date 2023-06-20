//
//  PlayerViewModel.swift
//  NepTunes
//
//  Created by Adam Różyński on 16/07/2021.
//

import Foundation
import AVKit
import Combine

private extension OnboardingScreen {
    var fileName: String? {
        switch self {
        case .welcome:
            return nil
        case .helper:
            return "helper"
        case .charging:
            return "usage"
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
                self?.updatePlayer(currentPage.fileName)
            }
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
