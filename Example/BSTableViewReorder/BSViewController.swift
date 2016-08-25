//
//  BSViewController.swift
//  BSTableViewReorder
//
//  Created by Bartłomiej Semańczyk on 23/09/15.
//  Copyright © 2015 Bartłomiej Semańczyk. All rights reserved.
//cd

import UIKit
import BSTableViewReorder

private let CellIdentifier = "CellIdentifier"

class BSViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, BSTableViewReorderDelegate {
    
    @IBOutlet var tableView: BSTableViewReorder!
    
    var data = [
        ["zero", "one"],
        ["two", "three", "four", "fife", "six"],
        ["seven", "eight", "nine", "ten", "eleven"],
        ["twelf", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"]
    ]
    
    //MARK: - Class Methods
    
    //MARK: - Initialization
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.reorderDelegate = self
    }
    
    //MARK: - Deinitialization
    
    //MARK: - Actions
    
    //MARK: - Public
    
    //MARK: - Internal
    
    //MARK: - Private
    
    //MARK: - Overridden
    
    //MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return data.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.tableView.adaptedNumberOfRowsInSection(section, withNumberOfRows: data[section].count)
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "section: \(section)"
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: CellIdentifier, for: indexPath) as! BSTableViewCell
        let adaptedIndexPath = self.tableView.adaptedIndexPathForRowAtIndexPath(indexPath)
        
        cell.label?.text = data[adaptedIndexPath.section][adaptedIndexPath.row]
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section != 1
    }
    
    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        
        let obj = data[sourceIndexPath.section][sourceIndexPath.row]
        
        data[sourceIndexPath.section].remove(at: sourceIndexPath.row)
        data[destinationIndexPath.section].insert(obj, at: destinationIndexPath.row)
    }
    
    //MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 40
    }
    
    //MARK: - BSTableViewReorderDelegate
    
    private func transformForSnapshotOfReorderingCell(atIndexPath indexPath: IndexPath) -> CATransform3D {
        
        var transform = CATransform3DIdentity
        transform.m34 = CGFloat(1.0 / -1000)
        
        transform = CATransform3DRotate(transform, CGFloat(20*M_PI / 180), 0, 1, 0)
        transform = CATransform3DRotate(transform, CGFloat(-15*M_PI / 180), 1, 0, 0)
        transform = CATransform3DTranslate(transform, -20, 0, 100)
        
        return transform
    }
}
