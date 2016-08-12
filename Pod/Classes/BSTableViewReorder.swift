//
//  BSTableViewReorder.swift
//  BSTableViewReorder
//
//  Created by Bartłomiej Semańczyk on 18/09/15.
//  Copyright © 2015 Railwaymen. All rights reserved.
//

import UIKit

private enum ReorderDirection {
    
    case Up
    case Down
    case Unknown
}

@objc public protocol BSTableViewReorderDelegate: class, UITableViewDelegate {
    
    optional var tableViewCanReorder: Bool { get set }
    optional var snapshotOpacity: Float { get set }
    
    optional func tableViewDidStartLongPress(gestureRecognizer: UILongPressGestureRecognizer)
    optional func tableViewDidEndLongPress(gestureRecognizer: UILongPressGestureRecognizer)
    optional func transformForSnapshotOfReorderingCellAtIndexPath(indexPath: NSIndexPath) -> CATransform3D
}

public class BSTableViewReorder: UITableView, UIScrollViewDelegate {
    
    public weak var reorderDelegate: BSTableViewReorderDelegate?
    
    private var longPressGestureRecognizer: UILongPressGestureRecognizer!
    private var snapshotOfReorderingCell: UIView?
    
    private var scrollRate: CGFloat = 0
    private var scrollDisplayLink: CADisplayLink?
    private var currentIndexPath: NSIndexPath?
    private var sourceIndexPath: NSIndexPath?
    private var previousRelativeLocation = CGPointZero
    
    private var numberOfRowsInTable: Int {
        
        get {
            
            var numberOfRows = 0
            
            for section in 0..<numberOfSections {
                numberOfRows += numberOfRowsInSection(section)
            }
            
            return numberOfRows
        }
    }
    
    private var relativeLocation: CGPoint {
        
        get {
            return longPressGestureRecognizer.locationInView(self)
        }
    }
    
    private var state: UIGestureRecognizerState {
        
        get {
            return longPressGestureRecognizer.state
        }
    }
    
    private var coveredIndexPath: NSIndexPath? {
        
        get {
            return indexPathForRowAtPoint(relativeLocation)
        }
    }
    
    private var coveredSection: Int? {
        
        get {
            
            var section: Int?
            
            for sectionIndex in 0..<numberOfSections {
                
                if CGRectContainsPoint(rectForSection(sectionIndex), relativeLocation) {
                    section = sectionIndex
                }
            }
            
            return section
        }
    }
    
    private var cellForCoveredIndexPath: UITableViewCell? {
        
        get {
            
            if let coveredIndexPath = coveredIndexPath {
                return cellForRowAtIndexPath(coveredIndexPath)
            }
            
            return nil
        }
    }
    
    private var cellForCurrentIndexPath: UITableViewCell? {
        
        get {
            
            if let currentIndexPath = currentIndexPath {
                return cellForRowAtIndexPath(currentIndexPath)
            } else {
                return nil
            }
        }
    }
    
    private var direction: ReorderDirection {
        
        get {
            
            if previousRelativeLocation.y == relativeLocation.y {
                return .Unknown
            }
            
            return previousRelativeLocation.y - relativeLocation.y > 0 ? .Up : .Down
        }
    }
    
    private var heightForCurrentCell: CGFloat {
        
        get {
            return rectForRowAtIndexPath(currentIndexPath!).size.height
        }
    }
    
    private var heightForCoveredCell: CGFloat {
        
        get {
            return rectForRowAtIndexPath(coveredIndexPath!).size.height
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
    
    //MARK: - Public
    
    public func adaptedNumberOfRowsInSection(section: Int, withNumberOfRows numberOfRows: Int) -> Int {
        
        var numberOfRows = numberOfRows
        
        if let currentIndexPath = currentIndexPath where currentIndexPath.section != sourceIndexPath?.section {
            
            if section == currentIndexPath.section {
                numberOfRows += 1
            } else if section == sourceIndexPath!.section {
                numberOfRows -= 1
            }
        }
        
        return numberOfRows
    }
    
    public func adaptedIndexPathForRowAtIndexPath(indexPath: NSIndexPath) -> NSIndexPath {
        
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
                indexPath = NSIndexPath(forRow: adaptedIndexPathRow, inSection: indexPath.section)
            }
        }
        
        return indexPath
    }
    
    //MARK: - Internal
    
    func longPressed() {
        
        if let tableViewCanReorder = reorderDelegate?.tableViewCanReorder where !tableViewCanReorder {
            return
        }
        
        guard numberOfRowsInTable > 0  else {
            
            cancelGestureRecognizer()
            return
        }
        
        switch state {
        case .Began:
            
            if let cell = cellForCoveredIndexPath {
                
                cell.setSelected(false, animated: false)
                cell.setHighlighted(false, animated: false)
                
                currentIndexPath = coveredIndexPath
                sourceIndexPath = coveredIndexPath
                
                if let sourceIndexPath = sourceIndexPath, canMoveSourceRow = dataSource?.tableView?(self, canMoveRowAtIndexPath: sourceIndexPath) where !canMoveSourceRow {
                        
                    cancelGestureRecognizer()
                    
                    return
                }
                
                setupSnapshot()
                
                reorderDelegate?.tableViewDidStartLongPress?(longPressGestureRecognizer)
                
                scrollDisplayLink = CADisplayLink(target: self, selector: #selector(scrollTable))
                scrollDisplayLink?.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSRunLoopCommonModes)
                cellForCurrentIndexPath?.hidden = true
            }
            
        case .Changed:
            
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
            
        case .Ended, .Cancelled:
            
            scrollDisplayLink?.invalidate()
            scrollDisplayLink = nil
            scrollRate = 0
            
            UIView.animateWithDuration(0.25, animations: {
                
                self.snapshotOfReorderingCell?.layer.transform = CATransform3DIdentity
                self.snapshotOfReorderingCell?.frame = self.rectForRowAtIndexPath(self.currentIndexPath!)
                
                if self.sourceIndexPath != self.currentIndexPath {
                    self.dataSource?.tableView?(self, moveRowAtIndexPath: self.sourceIndexPath!, toIndexPath: self.currentIndexPath!)
                }
                
                }, completion: { finished in
                    
                    self.reorderDelegate?.tableViewDidEndLongPress?(self.longPressGestureRecognizer)
                    self.cellForCurrentIndexPath?.hidden = false
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
        
        var newOffset = CGPointMake(contentOffset.x, contentOffset.y + scrollRate * 10)
        
        if contentSize.height < frame.size.height {
            
            newOffset = contentOffset
            
        } else if newOffset.y > contentSize.height - frame.size.height {
            
            newOffset.y = contentSize.height - frame.size.height
            
        } else if newOffset.y < 0 {
            
            newOffset = CGPointZero
        }
        
        contentOffset = newOffset
        
        updateTable()
        updateSnapshot()
        
        previousRelativeLocation = relativeLocation
    }
    
    //MARK: - Private
    
    private func cancelGestureRecognizer() {
        
        longPressGestureRecognizer.enabled = false
        longPressGestureRecognizer.enabled = true
    }
    
    private func updateTable() {
        
        if let coveredIndexPath = coveredIndexPath, let currentIndexPath = currentIndexPath where coveredIndexPath != currentIndexPath {
            
            let verticalPositionInCoveredCell = longPressGestureRecognizer.locationInView(cellForRowAtIndexPath(coveredIndexPath)).y
            
            if direction == .Down && heightForCoveredCell - verticalPositionInCoveredCell <= heightForCurrentCell / 2 || direction == .Up && verticalPositionInCoveredCell <= heightForCurrentCell / 2 {
                
                beginUpdates()
                moveRowAtIndexPath(currentIndexPath, toIndexPath: coveredIndexPath)
                
                cellForCurrentIndexPath?.hidden = true
                self.currentIndexPath = self.coveredIndexPath
                
                endUpdates()
            }
            
        } else if let coveredSection = coveredSection where numberOfRowsInSection(coveredSection) == 0 {
            
            let newIndexPath = NSIndexPath(forRow: 0, inSection: coveredSection)
            
            beginUpdates()
            moveRowAtIndexPath(currentIndexPath!, toIndexPath: newIndexPath)
            
            cellForCurrentIndexPath?.hidden = true
            currentIndexPath = newIndexPath
            
            endUpdates()
        }
    }
    
    private func updateSnapshot() {
        
        if relativeLocation.y >= 0 && relativeLocation.y <= contentSize.height + 50 {
            snapshotOfReorderingCell?.center = CGPointMake(center.x, relativeLocation.y)
        }
    }
    
    private func setupSnapshot() {
        
        UIGraphicsBeginImageContextWithOptions(cellForCoveredIndexPath!.bounds.size, false, 0)
        cellForCoveredIndexPath!.layer.renderInContext(UIGraphicsGetCurrentContext()!)
        
        snapshotOfReorderingCell = UIImageView(image: UIGraphicsGetImageFromCurrentImageContext())
        addSubview(snapshotOfReorderingCell!)
        
        let frameForCoveredIndexPath = rectForRowAtIndexPath(coveredIndexPath!)
        snapshotOfReorderingCell?.frame = CGRectOffset(snapshotOfReorderingCell!.bounds, frameForCoveredIndexPath.origin.x, frameForCoveredIndexPath.origin.y)
        
        snapshotOfReorderingCell?.layer.masksToBounds = false
        snapshotOfReorderingCell?.layer.shadowColor = UIColor.blackColor().CGColor
        snapshotOfReorderingCell?.layer.shadowOffset = CGSizeMake(0, 0)
        snapshotOfReorderingCell?.layer.shadowRadius = 4
        snapshotOfReorderingCell?.layer.shadowOpacity = 0.7
        snapshotOfReorderingCell?.layer.opacity = reorderDelegate?.snapshotOpacity ?? 1
        
        UIView.animateWithDuration(0.25) {
            
            self.snapshotOfReorderingCell?.layer.transform = self.reorderDelegate?.transformForSnapshotOfReorderingCellAtIndexPath?(self.currentIndexPath!) ?? CATransform3DMakeScale(1.1, 1.1, 1)
            self.snapshotOfReorderingCell?.center = CGPointMake(self.center.x, self.relativeLocation.y)
        }
        
        UIGraphicsEndImageContext()
    }
    
    //MARK: - Overridden
}
