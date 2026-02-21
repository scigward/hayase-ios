//
//  VideoListViewController.swift
//  Fin
//
//  Created by Tieria C.Monk on 8/1/16.
//  Copyright © 2016 Tieria C.Monk. All rights reserved.
//

import UIKit
import CoreData

class VideoListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var torrentEntity: Torrents? = nil
    var videoResultsController: NSFetchedResultsController<Videos>? = nil
    var videoService: VideoService? = nil
    var stopUpdatingVideoTable: Bool = false
    @IBOutlet weak var videoTableView: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()

        let fetchRequest = NSFetchRequest<Videos>(entityName: Videos.entityName)
        let sortDescriptor = NSSortDescriptor(key: "videoName", ascending: true)
        fetchRequest.sortDescriptors = [sortDescriptor]
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        self.videoResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, sectionNameKeyPath: nil, cacheName: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(HandleLocalVideosDidUpdate), name: NSNotification.Name(VideoService.LocalVideosDidUpdateNotification), object: nil)

        if let targetTorrent = self.torrentEntity {
            videoService = VideoService(torrentEntity: targetTorrent)
            videoService!.UpdateLocalVideo()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if self.isMovingToParent {
            self.stopUpdatingVideoTable = false
            DispatchQueue.global(qos: .default).async {
                while !self.stopUpdatingVideoTable {
                    DispatchQueue.main.async {
                        self.videoTableView.reloadData()
                    }
                    sleep(1)
                }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        if self.isMovingFromParent {
            super.viewWillDisappear(animated)
            self.videoService?.ClearCurrentTorrentEntityAndVideos()
            self.stopUpdatingVideoTable = true
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    // MARK: - Table view data source

    func numberOfSections(in tableView: UITableView) -> Int {
        return self.videoResultsController?.sections?.count ?? 0
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.videoResultsController?.sections?[section].objects?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "VideoProtoCell1", for: indexPath)
        let video = self.videoResultsController?.object(at: indexPath)

        cell.selectionStyle = .none
        cell.textLabel?.text = video?.videoName ?? ""
        cell.detailTextLabel?.text = "\(video?.videoSize ?? 0)MB"

        guard let vs = self.videoService, let video = video, let indexNum = video.videoIndex else { return cell }
        let index = UInt(indexNum.intValue)
        let isDoNotDownload = vs.CheckIsDoNotDownloadForFileIndex(index) ?? true
        if !isDoNotDownload {
            let progress = vs.UpdateProgressForFileIndex(index)
            cell.detailTextLabel?.text?.append(" Progress:\(progress * 100)%")
        } else {
            cell.detailTextLabel?.text?.append(" - Tap to start downloading")
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let video = self.videoResultsController?.object(at: indexPath),
              let vs = self.videoService,
              let indexNum = video.videoIndex else { return }
        let index = UInt(indexNum.intValue)
        if vs.CheckIsDoNotDownloadForFileIndex(index) ?? false {
            vs.SetDoNotDownloadForFileIndex(index, flag: false)
            DispatchQueue.main.async {
                self.videoTableView.reloadData()
            }
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)

        if let s = sender as? UITableViewCell {
            guard let indexPath = videoTableView.indexPath(for: s) else { return }
            guard let video = self.videoResultsController?.object(at: indexPath) else { return }
            guard let indexNum = video.videoIndex else { return }
            guard let vs = self.videoService else { return }
            vs.UpdateFilePathForFileIndex(UInt(indexNum.intValue))
            let destination = segue.destination as! VideoPlayerController
            destination.videoEntity = video
        }
    }

    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        if let s = sender as? UITableViewCell {
            guard let indexPath = self.videoTableView.indexPath(for: s) else { return false }
            guard let video = self.videoResultsController?.object(at: indexPath) else { return false }
            return video.videoDownloadPercent?.floatValue == 1.0
        }
        return true
    }

    private func UpdateFetchedResults() {
        do {
            try self.videoResultsController?.performFetch()
        } catch {
            print("Error fetching torrents from core data")
        }
    }

    @objc private func HandleLocalVideosDidUpdate(_ notification: Notification) {
        self.UpdateFetchedResults()
        DispatchQueue.main.async {
            self.videoTableView.reloadData()
        }
    }
}
