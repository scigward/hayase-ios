//
//  TorrentListViewControllerTableViewController.swift
//  Fin
//
//  Created by Tieria C.Monk on 8/1/16.
//  Copyright © 2016 Tieria C.Monk. All rights reserved.
//

import UIKit
import CoreData

class TorrentListViewController: UIViewController, UISearchBarDelegate, UITableViewDelegate, UITableViewDataSource {
    let defaultPredicate = NSPredicate(format: "torrentFlagTemp == YES")
    let defaultSortDescriptor = NSSortDescriptor(key: "torrentOrder", ascending: true)

    var animeEntity: Animes? = nil
    var torrentResultsController: NSFetchedResultsController<Torrents>? = nil
    @IBOutlet weak var torrentTableView: UITableView!
    @IBOutlet weak var torrentSearchBar: UISearchBar!

    override func viewDidLoad() {
        super.viewDidLoad()
        print(self.animeEntity as Any)

        torrentSearchBar.enablesReturnKeyAutomatically = false

        let fetchRequest = NSFetchRequest<Torrents>(entityName: Torrents.entityName)
        fetchRequest.predicate = self.defaultPredicate
        fetchRequest.sortDescriptors = [self.defaultSortDescriptor]
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        self.torrentResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, sectionNameKeyPath: nil, cacheName: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(HandleLocalTorrentDidUpdate), name: NSNotification.Name(TorrentService.LocalTorrentsDidUpdateNotification), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(HandleKeyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(HandleKeyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)

        let tap = UITapGestureRecognizer(target: self, action: #selector(TapHandler))
        tap.cancelsTouchesInView = false
        self.view.addGestureRecognizer(tap)

        let searchString = TorrentService.UtilMakeShortSearchString(self.animeEntity?.animeTitleEnglish ?? "")
        print(searchString)
        TorrentService.sharedTorrentService.UpdateTempTorrentsWith(searchString, sortBy: TorrentService.SortBy.Seeders)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let idxs = self.torrentTableView.indexPathsForSelectedRows {
            for idx in idxs {
                self.torrentTableView.deselectRow(at: idx, animated: true)
            }
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)

        let destination = segue.destination as! VideoListViewController
        let indexPath = torrentTableView.indexPathsForSelectedRows?[0]

        guard let targetIndex = indexPath else { return }
        destination.torrentEntity = torrentResultsController?.object(at: targetIndex)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.FilterResultsWithString(searchText)
        self.torrentTableView.reloadData()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    // MARK: - Table view data source

    func numberOfSections(in tableView: UITableView) -> Int {
        return torrentResultsController?.sections?.count ?? 0
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return torrentResultsController?.sections?[section].objects?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TorrentProtoCell1", for: indexPath)

        let torrent = torrentResultsController?.object(at: indexPath)
        cell.textLabel?.text = torrent?.torrentName
        cell.detailTextLabel?.text = String(format: "S:%@ L:%@ D:%@ Size:%@MB",
                                            torrent?.torrentSeeders ?? 0,
                                            torrent?.torrentLeechers ?? 0,
                                            torrent?.torrentDownloads ?? 0,
                                            torrent?.torrentSize ?? 0)
        return cell
    }

    private func UpdateFetchedResults() {
        do {
            try torrentResultsController?.performFetch()
        } catch {
            print("Error fetching torrents from core data")
        }
    }

    private func FilterResultsWithString(_ searchString: String) {
        let context = CoreDataService.sharedCoreDataService.mainQueueContext
        let fetchRequest = NSFetchRequest<Torrents>(entityName: Torrents.entityName)
        if searchString == "" {
            fetchRequest.predicate = self.defaultPredicate
            fetchRequest.sortDescriptors = [self.defaultSortDescriptor]
        } else {
            let separatedString = searchString.components(separatedBy: CharacterSet.whitespaces)
            var subPredicates = [NSPredicate]()
            for subString in separatedString {
                guard subString.count > 0 else { continue }
                subPredicates.append(NSPredicate(format: "torrentName CONTAINS[cd] \"\(subString)\" && torrentFlagTemp == YES"))
            }
            let filterPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: subPredicates)
            fetchRequest.predicate = filterPredicate
            fetchRequest.sortDescriptors = [self.defaultSortDescriptor]
        }
        self.torrentResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, sectionNameKeyPath: nil, cacheName: nil)
        UpdateFetchedResults()
    }

    @objc private func HandleLocalTorrentDidUpdate(_ notification: Notification) {
        UpdateFetchedResults()
        self.torrentTableView.reloadData()
    }

    @objc private func HandleKeyboardWillShow(_ notification: Notification) {
        self.torrentTableView.adjustInsetsForWillShowKeyboardNotification(notification)
    }

    @objc private func HandleKeyboardWillHide(_ notification: Notification) {
        self.torrentTableView.adjustInsetsForWillHideKeyboardNotification(notification)
    }

    @objc private func TapHandler() {
        self.torrentSearchBar.resignFirstResponder()
    }
}
