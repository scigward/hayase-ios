//
//  VideoPlayerController.swift
//  FinalProject
//
//  Created by Tieria C.Monk on 8/18/16.
//
//

import AVKit

class VideoPlayerController: AVPlayerViewController {
    var videoEntity: Videos? = nil

    override func viewDidLoad() {
        guard let videoPath = videoEntity?.videoPath else { return }
        let url = URL(fileURLWithPath: videoPath)
        DispatchQueue.global(qos: .default).async {
            let player = AVPlayer(url: url)
            DispatchQueue.main.async {
                self.player = player
                player.play()
            }
        }
    }
}
