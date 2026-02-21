//
//  ViewController.swift
//  Fin
//
//  Created by Tieria C.Monk on 8/1/16.
//  Copyright © 2016 Tieria C.Monk. All rights reserved.
//

import UIKit
import CoreData

class BrowseAnimeViewController: UIViewController, UISearchBarDelegate, UICollectionViewDelegate, UICollectionViewDataSource {

    var lastSearchString: String = ""
    var animeResultsController: NSFetchedResultsController<Animes>? = nil
    @IBOutlet weak var animeCollectionView: UICollectionView!
    @IBOutlet weak var animeSearchBar: UISearchBar!

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        let destination = segue.destination as! TorrentListViewController
        let indexPath = animeCollectionView.indexPathsForSelectedItems?[0]

        guard let targetIndex = indexPath else { return }
        destination.animeEntity = animeResultsController?.object(at: targetIndex)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        animeSearchBar.enablesReturnKeyAutomatically = false
        let inset = animeCollectionView.frame.width * 0.018
        self.animeCollectionView.contentInset = UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)

        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let fetchRequest = NSFetchRequest<Animes>(entityName: Animes.entityName)
        fetchRequest.predicate = NSPredicate(format: "animeFlagTemp == YES")
        let sortDescriptor = NSSortDescriptor(key: "animeNextEpsTime", ascending: false)
        fetchRequest.sortDescriptors = [sortDescriptor]
        self.animeResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, sectionNameKeyPath: nil, cacheName: nil)
        self.UpdateFetchedResults()

        NotificationCenter.default.addObserver(self, selector: #selector(HandleLocalAnimeDidUpdate), name: NSNotification.Name(AnimeService.LocalAnimeDidUpdateNotification), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(HandleLocalAnimeUpdateFailed), name: NSNotification.Name(AnimeService.LocalAnimeUpdateFailedNotification), object: nil)

        let tap = UITapGestureRecognizer(target: self, action: #selector(TapHandler))
        tap.cancelsTouchesInView = false
        self.view.addGestureRecognizer(tap)

        AnimeService.sharedAnimeService.UpdateTempWithAiringAnimes()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if let idxs = self.animeCollectionView.indexPathsForSelectedItems {
            for idx in idxs {
                self.animeCollectionView.deselectItem(at: idx, animated: true)
            }
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let text = self.animeSearchBar.text else { return }
        self.SearchWithString(text)
        self.animeSearchBar.resignFirstResponder()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        self.SearchWithString("")
        searchBar.resignFirstResponder()
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return animeResultsController?.sections?.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return animeResultsController?.sections?[section].objects?.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = animeCollectionView.dequeueReusableCell(withReuseIdentifier: "AnimeProtoCell1", for: indexPath) as! AnimeCollectionViewCell
        guard let anime = animeResultsController?.object(at: indexPath) else { return cell }

        let score = anime.animeScore?.floatValue ?? 0.0
        cell.shortDescription.text = String(format: "%@\nScore: %@", anime.animeTitleEnglish ?? "", score == 0.0 ? "N/A" : String(score))

        DispatchQueue.main.async { cell.image.alpha = 0 }
        UrlIf: if let urlString = anime.animeImgM {
            guard let url = URL(string: urlString) else { break UrlIf }

            let task = URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let imgData = data else { return }
                let image = UIImage(data: imgData)
                DispatchQueue.main.async {
                    cell.image.image = image
                    let animation = CABasicAnimation(keyPath: "opacity")
                    animation.duration = 0.5
                    animation.fromValue = 0
                    animation.toValue = 1
                    cell.image.layer.add(animation, forKey: "animateOpacity")
                    cell.image.alpha = 1
                }
            }
            task.resume()
        }

        cell.shortDescription.layoutIfNeeded()
        cell.shortDescription.setContentOffset(CGPoint(x: 0, y: 5), animated: false)
        cell.shortDescription.textContainer.lineBreakMode = .byCharWrapping

        cell.contentView.layer.cornerRadius = 3.0
        cell.contentView.layer.borderWidth = 0.5
        cell.contentView.layer.borderColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.9).cgColor
        cell.contentView.layer.masksToBounds = true

        cell.layer.shadowColor = UIColor.black.cgColor
        cell.layer.shadowOffset = CGSize(width: 0, height: 0)
        cell.layer.shadowRadius = 2.0
        cell.layer.shadowOpacity = 0.3
        cell.layer.masksToBounds = false
        cell.layer.shadowPath = UIBezierPath(roundedRect: cell.bounds, cornerRadius: cell.contentView.layer.cornerRadius).cgPath

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let targetWidth = collectionView.frame.width * 0.29
        return CGSize(width: targetWidth, height: targetWidth)
    }

    private func UpdateFetchedResults() {
        do {
            try animeResultsController?.performFetch()
        } catch {
            print("Error fetching animes from core data")
        }
    }

    private func SearchWithString(_ searchString: String) {
        guard searchString != self.lastSearchString else { return }

        self.lastSearchString = searchString
        if searchString == "" {
            AnimeService.sharedAnimeService.UpdateTempWithAiringAnimes()
        } else {
            AnimeService.sharedAnimeService.UpdateTempAnimesWithSearchString(searchString)
        }
    }

    @objc private func HandleLocalAnimeDidUpdate(_ notification: Notification) {
        UpdateFetchedResults()
        self.animeCollectionView.reloadData()
    }

    @objc private func HandleLocalAnimeUpdateFailed(_ notification: Notification) {
        let error = notification.object as! NSError
        switch error.code {
        case 4: // AnimeService.AnimeError.emptyResult
            self.UpdateFetchedResults()
            self.animeCollectionView.reloadData()
        default:
            break
        }
    }

    @objc private func TapHandler() {
        guard let text = self.animeSearchBar.text else { return }
        self.SearchWithString(text)
        self.animeSearchBar.resignFirstResponder()
    }
}
