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
    
    optional func transformForSnapshotOfReorderingCellAtIndexPath(indexPath: NSIndexPath) -> CGAffineTransform
}

public class BSTableViewReorder: UITableView, UIScrollViewDelegate {
    
    public weak var reorderDelegate: BSTableViewReorderDelegate?
    
    private var longPressGestureRecognizer: UILongPressGestureRecognizer!
    private var snapshotOfReorderingCell: UIImageView?
    
    private var scrollRate: CGFloat = 0
    private var scrollDisplayLink: CADisplayLink?
    private var currentIndexPath: NSIndexPath?
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
            return cellForRowAtIndexPath(coveredIndexPath!)
        }
    }
    
    private var cellForCurrentIndexPath: UITableViewCell? {
        get {
            return cellForRowAtIndexPath(currentIndexPath!)
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
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: Selector("longPressed"))
        addGestureRecognizer(longPressGestureRecognizer)
    }
    
    func longPressed() {
        
        if let tableViewCanReorder = reorderDelegate?.tableViewCanReorder where !tableViewCanReorder {
            return
        }
        
        guard numberOfRowsInTable > 0  else {

            longPressGestureRecognizer.enabled = false
            longPressGestureRecognizer.enabled = true
            return
        }
        
        switch state {
        case .Began:
            
            if let cell = cellForCoveredIndexPath {

                cell.setSelected(false, animated: false)
                cell.setHighlighted(false, animated: false)
                
                currentIndexPath = coveredIndexPath
                setupSnapshot()
   
                scrollDisplayLink = CADisplayLink(target: self, selector: Selector("scrollTable"))
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
            
            UIView.animateWithDuration(0.25, animations: { [unowned self] in
                
                self.snapshotOfReorderingCell?.transform = CGAffineTransformIdentity
                self.snapshotOfReorderingCell?.frame = self.rectForRowAtIndexPath(self.currentIndexPath!)
                
                }, completion: { finished in
                    
                    self.cellForCurrentIndexPath?.hidden = false
                    self.snapshotOfReorderingCell?.removeFromSuperview()
                    self.snapshotOfReorderingCell = nil
                    self.currentIndexPath = nil
            })
            
        default:
            ()
        }
    }
    
    func scrollTable() {
        
        guard relativeLocation.y > 0 && relativeLocation.y <= contentSize.height + 50 else {

            longPressGestureRecognizer.enabled = false
            longPressGestureRecognizer.enabled = true
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
    
    private func updateTable() {
        
        if coveredIndexPath != nil && coveredIndexPath! != currentIndexPath! {
            
            let verticalPositionInCoveredCell = longPressGestureRecognizer.locationInView(cellForRowAtIndexPath(coveredIndexPath!)).y
            
            if direction == .Down && heightForCoveredCell - verticalPositionInCoveredCell <= heightForCurrentCell / 2 || direction == .Up && verticalPositionInCoveredCell <= heightForCurrentCell / 2 {
                
                beginUpdates()
                moveRowAtIndexPath(currentIndexPath!, toIndexPath: coveredIndexPath!)
                dataSource?.tableView?(self, moveRowAtIndexPath: self.currentIndexPath!, toIndexPath: self.coveredIndexPath!)
                currentIndexPath = coveredIndexPath
                endUpdates()
            }
        } else if let coveredSection = coveredSection where numberOfRowsInSection(coveredSection) == 0 {
            
            let newIndexPath = NSIndexPath(forRow: 0, inSection: coveredSection)
            
            beginUpdates()
            moveRowAtIndexPath(currentIndexPath!, toIndexPath: newIndexPath)
            dataSource?.tableView?(self, moveRowAtIndexPath: self.currentIndexPath!, toIndexPath: newIndexPath)
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
        
        let rect = rectForRowAtIndexPath(coveredIndexPath!)
        snapshotOfReorderingCell?.frame = CGRectOffset(snapshotOfReorderingCell!.bounds, rect.origin.x, rect.origin.y)
        
        snapshotOfReorderingCell?.layer.masksToBounds = false
        snapshotOfReorderingCell?.layer.shadowColor = UIColor.blackColor().CGColor
        snapshotOfReorderingCell?.layer.shadowOffset = CGSizeMake(0, 0)
        snapshotOfReorderingCell?.layer.shadowRadius = 4
        snapshotOfReorderingCell?.layer.shadowOpacity = 0.7
        snapshotOfReorderingCell?.layer.opacity = reorderDelegate?.snapshotOpacity ?? 1
        
        UIView.animateWithDuration(0.25, animations: {
            
            self.snapshotOfReorderingCell?.transform = self.reorderDelegate?.transformForSnapshotOfReorderingCellAtIndexPath?(self.currentIndexPath!) ?? CGAffineTransformMakeScale(1.1, 1.1)
            self.snapshotOfReorderingCell?.center = CGPointMake(self.center.x, self.relativeLocation.y)
        })
        
        UIGraphicsEndImageContext()
    }
}