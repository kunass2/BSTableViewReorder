//
//  BSTableViewReorder.swift
//  BSTableViewReorder
//
//  Created by Bartłomiej Semańczyk on 18/09/15.
//  Copyright © 2015 Railwaymen. All rights reserved.
//

import UIKit

@objc public protocol BSTableViewReorderDelegate: class, UITableViewDelegate {
    
    @objc optional var tableViewCanReorder: Bool { get set }
    @objc optional var snapshotOpacity: Float { get set }
    
    @objc optional func tableViewDidStartLongPress(gestureRecognizer: UILongPressGestureRecognizer)
    @objc optional func tableViewDidEndLongPress(gestureRecognizer: UILongPressGestureRecognizer)
    @objc optional func transformForSnapshotOfReorderingCell(atIndexPath indexPath: IndexPath) -> CATransform3D
}

open class BSTableViewReorder: UITableView, UIScrollViewDelegate {
    
    open weak var reorderDelegate: BSTableViewReorderDelegate?
    
    private enum ReorderDirection {
        
        case down
        case unknown
        case up
    }
    
    private var longPressGestureRecognizer: UILongPressGestureRecognizer!
    private var snapshotOfReorderingCell: UIView?
    
    private var scrollRate: CGFloat = 0
    private var scrollDisplayLink: CADisplayLink?
    private var currentIndexPath: IndexPath?
    private var sourceIndexPath: IndexPath?
    private var previousRelativeLocation = CGPoint.zero
    
    private var numberOfRowsInTable: Int {
        
        get {
            
            var numberOfRows = 0
            
            for section in 0..<numberOfSections {
                numberOfRows += self.numberOfRows(inSection: section)
            }
            
            return numberOfRows
        }
    }
    
    private var relativeLocation: CGPoint {
        
        get {
            return longPressGestureRecognizer.location(in: self)
        }
    }
    
    private var state: UIGestureRecognizerState {
        
        get {
            return longPressGestureRecognizer.state
        }
    }
    
    private var coveredIndexPath: IndexPath? {
        
        get {
            return indexPathForRow(at: relativeLocation)
        }
    }
    
    private var coveredSection: Int? {
        
        get {
            
            var section: Int?
            
            for sectionIndex in 0..<numberOfSections {
                
                if rect(forSection: sectionIndex).contains(relativeLocation) {
                    section = sectionIndex
                }
            }
            
            return section
        }
    }
    
    private var cellForCoveredIndexPath: UITableViewCell? {
        
        get {
            
            if let coveredIndexPath = coveredIndexPath {
                return cellForRow(at: coveredIndexPath)
            }
            
            return nil
        }
    }
    
    private var cellForCurrentIndexPath: UITableViewCell? {
        
        get {
            
            if let currentIndexPath = currentIndexPath {
                return cellForRow(at: currentIndexPath)
            } else {
                return nil
            }
        }
    }
    
    private var direction: ReorderDirection {
        
        get {
            
            if previousRelativeLocation.y == relativeLocation.y {
                return .unknown
            }
            
            return previousRelativeLocation.y - relativeLocation.y > 0 ? .up : .down
        }
    }
    
    private var heightForCurrentCell: CGFloat {
        
        get {
            return rectForRow(at: currentIndexPath!).size.height
        }
    }
    
    private var heightForCoveredCell: CGFloat {
        
        get {
            return rectForRow(at: coveredIndexPath!).size.height
        }
    }
    
    //MARK: - Class Methods
    
    //MARK: - Initialization
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressed))
        addGestureRecognizer(longPressGestureRecognizer)
    }
    
    //MARK: - Deinitialization
    
    //MARK: - Actions
    
    //MARK: - Open
    
    open func adaptedNumberOfRowsInSection(_ section: Int, withNumberOfRows numberOfRows: Int) -> Int {
        
        var numberOfRows = numberOfRows
        
        if let currentIndexPath = currentIndexPath , currentIndexPath.section != sourceIndexPath?.section {
            
            if section == currentIndexPath.section {
                
                numberOfRows += 1
                
            } else if section == sourceIndexPath!.section {
                
                numberOfRows -= 1
            }
        }
        
        return numberOfRows
    }
    
    open func adaptedIndexPathForRowAtIndexPath(_ indexPath: IndexPath) -> IndexPath {
        
        var indexPath = indexPath
        
        if let currentIndexPath = currentIndexPath, let sourceIndexPath = sourceIndexPath {
            
            var adaptedIndexPathRow: Int? = nil
            
            if indexPath == currentIndexPath {
                
                indexPath = sourceIndexPath
                
            } else if currentIndexPath.section == sourceIndexPath.section {
                
                if indexPath.row >= sourceIndexPath.row && indexPath.row < currentIndexPath.row {
                    
                    adaptedIndexPathRow = indexPath.row + 1
                    
                } else if indexPath.row <= sourceIndexPath.row && indexPath.row > currentIndexPath.row {
                    
                    adaptedIndexPathRow = indexPath.row - 1
                }
                
            } else {
                
                if indexPath.section == sourceIndexPath.section && indexPath.row >= sourceIndexPath.row {
                    
                    adaptedIndexPathRow = indexPath.row + 1
                    
                } else if indexPath.section == currentIndexPath.section && indexPath.row > currentIndexPath.row {
                    
                    adaptedIndexPathRow = indexPath.row - 1
                }
            }
            
            if let adaptedIndexPathRow = adaptedIndexPathRow {
                indexPath = IndexPath(row: adaptedIndexPathRow, section: indexPath.section)
            }
        }
        
        return indexPath
    }
    
    //MARK: - Internal
    
    func longPressed() {
        
        if let tableViewCanReorder = reorderDelegate?.tableViewCanReorder , !tableViewCanReorder {
            return
        }
        
        guard numberOfRowsInTable > 0  else {
            
            cancelGestureRecognizer()
            return
        }
        
        switch state {
        case .began:
            
            if let cell = cellForCoveredIndexPath {
                
                cell.setSelected(false, animated: false)
                cell.setHighlighted(false, animated: false)
                
                currentIndexPath = coveredIndexPath
                sourceIndexPath = coveredIndexPath
                
                if let sourceIndexPath = sourceIndexPath, let canMoveSourceRow = dataSource?.tableView?(self, canMoveRowAt: sourceIndexPath) , !canMoveSourceRow {
                        
                    cancelGestureRecognizer()
                    
                    return
                }
                
                setupSnapshot()
                
                reorderDelegate?.tableViewDidStartLongPress?(gestureRecognizer: longPressGestureRecognizer)
                
                scrollDisplayLink = CADisplayLink(target: self, selector: #selector(scrollTable))
                scrollDisplayLink?.add(to: RunLoop.main, forMode: RunLoopMode.commonModes)
                cellForCurrentIndexPath?.isHidden = true
            }
            
        case .changed:
            
            let scrollZoneHeight = bounds.size.height / 6
            let bottomScrollBeginning = contentOffset.y + frame.size.height - scrollZoneHeight
            let topScrollBeginning = contentOffset.y + scrollZoneHeight
            
            if relativeLocation.y >= bottomScrollBeginning {
                
                scrollRate = (relativeLocation.y - bottomScrollBeginning) / scrollZoneHeight
                
            } else if relativeLocation.y <= topScrollBeginning {
                
                scrollRate = (relativeLocation.y - topScrollBeginning) / scrollZoneHeight
                
            } else {
                scrollRate = 0
            }
            
        case .ended, .cancelled:
            
            scrollDisplayLink?.invalidate()
            scrollDisplayLink = nil
            scrollRate = 0
            
            UIView.animate(withDuration: 0.25, animations: {
                
                self.snapshotOfReorderingCell?.layer.transform = CATransform3DIdentity
                self.snapshotOfReorderingCell?.frame = self.rectForRow(at: self.currentIndexPath!)
                
                if self.sourceIndexPath != self.currentIndexPath {
                    self.dataSource?.tableView?(self, moveRowAt: self.sourceIndexPath!, to: self.currentIndexPath!)
                }
                
                }, completion: { finished in
                    
                    self.reorderDelegate?.tableViewDidEndLongPress?(gestureRecognizer: self.longPressGestureRecognizer)
                    self.cellForCurrentIndexPath?.isHidden = false
                    self.snapshotOfReorderingCell?.removeFromSuperview()
                    self.snapshotOfReorderingCell = nil
                    self.currentIndexPath = nil
                    self.sourceIndexPath = nil
            })
            
        default:
            ()
        }
    }
    
    func scrollTable() {
        
        guard relativeLocation.y > 0 && relativeLocation.y <= contentSize.height + 50 else {
            return
        }
        
        var newOffset = CGPoint(x: contentOffset.x, y: contentOffset.y + scrollRate * 10)
        
        if contentSize.height < frame.size.height {
            
            newOffset = contentOffset
            
        } else if newOffset.y > contentSize.height - frame.size.height {
            
            newOffset.y = contentSize.height - frame.size.height
            
        } else if newOffset.y < 0 {
            
            newOffset = CGPoint.zero
        }
        
        contentOffset = newOffset
        
        updateTable()
        updateSnapshot()
        
        previousRelativeLocation = relativeLocation
    }
    
    //MARK: - Private
    
    private func cancelGestureRecognizer() {
        
        longPressGestureRecognizer.isEnabled = false
        longPressGestureRecognizer.isEnabled = true
    }
    
    private func updateTable() {
        
        if let coveredIndexPath = coveredIndexPath, let currentIndexPath = currentIndexPath , coveredIndexPath != currentIndexPath {
            
            let verticalPositionInCoveredCell = longPressGestureRecognizer.location(in: cellForRow(at: coveredIndexPath)).y
            
            if direction == .down && heightForCoveredCell - verticalPositionInCoveredCell <= heightForCurrentCell / 2 || direction == .up && verticalPositionInCoveredCell <= heightForCurrentCell / 2 {
                
                beginUpdates()
                moveRow(at: currentIndexPath, to: coveredIndexPath)
                
                cellForCurrentIndexPath?.isHidden = true
                self.currentIndexPath = self.coveredIndexPath
                
                endUpdates()
            }
            
        } else if let coveredSection = coveredSection , numberOfRows(inSection: coveredSection) == 0 {
            
            let newIndexPath = IndexPath(row: 0, section: coveredSection)
            
            beginUpdates()
            moveRow(at: currentIndexPath!, to: newIndexPath)
            
            cellForCurrentIndexPath?.isHidden = true
            currentIndexPath = newIndexPath
            
            endUpdates()
        }
    }
    
    private func updateSnapshot() {
        
        if relativeLocation.y >= 0 && relativeLocation.y <= contentSize.height + 50 {
            snapshotOfReorderingCell?.center = CGPoint(x: center.x, y: relativeLocation.y)
        }
    }
    
    private func setupSnapshot() {
        
        UIGraphicsBeginImageContextWithOptions(cellForCoveredIndexPath!.bounds.size, false, 0)
        cellForCoveredIndexPath!.layer.render(in: UIGraphicsGetCurrentContext()!)
        
        snapshotOfReorderingCell = UIImageView(image: UIGraphicsGetImageFromCurrentImageContext())
        addSubview(snapshotOfReorderingCell!)
        
        let frameForCoveredIndexPath = rectForRow(at: coveredIndexPath!)
        snapshotOfReorderingCell?.frame = snapshotOfReorderingCell!.bounds.offsetBy(dx: frameForCoveredIndexPath.origin.x, dy: frameForCoveredIndexPath.origin.y)
        
        snapshotOfReorderingCell?.layer.masksToBounds = false
        snapshotOfReorderingCell?.layer.shadowColor = UIColor.black.cgColor
        snapshotOfReorderingCell?.layer.shadowOffset = CGSize(width: 0, height: 0)
        snapshotOfReorderingCell?.layer.shadowRadius = 4
        snapshotOfReorderingCell?.layer.shadowOpacity = 0.7
        snapshotOfReorderingCell?.layer.opacity = reorderDelegate?.snapshotOpacity ?? 1
        
        UIView.animate(withDuration: 0.25) {
            
            self.snapshotOfReorderingCell?.layer.transform = self.reorderDelegate?.transformForSnapshotOfReorderingCell?(atIndexPath: self.currentIndexPath!) ?? CATransform3DMakeScale(1.1, 1.1, 1)
            self.snapshotOfReorderingCell?.center = CGPoint(x: self.center.x, y: self.relativeLocation.y)
        }
        
        UIGraphicsEndImageContext()
    }
    
    //MARK: - Overridden
}
