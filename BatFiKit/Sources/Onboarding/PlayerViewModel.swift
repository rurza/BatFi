//
//  PlayerViewModel.swift
//  NepTunes
//
//  Created by Adam Różyński on 16/07/2021.
//

import Foundation
import AVKit
import Combine

class PlayerViewModel: ObservableObject {

    private var cancellables = Set<AnyCancellable>()
    let item: AVPlayerItem

    lazy var player: AVPlayer = {
        let player = AVPlayer(playerItem: item)
        player.volume = 0
        player.actionAtItemEnd = .none

        return player
    }()

    init(name: String) {
        let urlString = "https://files.micropixels.software/batfi/" + name + ".mp4"
        let url = URL(string: urlString)!
        let asset = AVURLAsset(url: url)
        item = AVPlayerItem(asset: asset)
        setUpSubscribers()
    }

    func setUpSubscribers() {
        NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .map { $0.object as? AVPlayerItem }
            .sink {
                $0?.seek(to: CMTime.zero, completionHandler: nil)
            }
            .store(in: &cancellables)
    }

    func play() {
        player.seek(to: CMTime.zero)
        player.play()
    }
    
    func reset() {
        player.pause()
        player.seek(to: CMTime.zero)
    }

    var isPlaying: Bool {
        player.timeControlStatus == .playing
    }

}
