//
//  SourceTimelineView.swift
//  RxMarbles
//
//  Created by Roman Tutubalin on 21.01.16.
//  Copyright © 2016 AnjLab. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa

class SourceSequenceView: SequenceView, UIDynamicAnimatorDelegate {
    var addButton = UIButton(type: .ContactAdd)
    let longPressGestureRecorgnizer = UILongPressGestureRecognizer()
    var animator: UIDynamicAnimator?
    private var _panEventView: EventView?
    private var _ghostEventView: EventView?
    
    private var _needRefreshEventViews: Bool = true
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(frame: CGRect, scene: SceneView) {
        super.init(frame: frame)
        userInteractionEnabled = true
        clipsToBounds = false
        sceneView = scene
        
        animator = UIDynamicAnimator(referenceView: self)
        animator?.delegate = self
        
        longPressGestureRecorgnizer.minimumPressDuration = 0.0
        
        addGestureRecognizer(longPressGestureRecorgnizer)
        
        addButton.hidden = true
        longPressGestureRecorgnizer
            .rx_event
            .subscribeNext {
                [unowned self] r in self._handleLongPressGestureRecognizer(r)
            }
            .addDisposableTo(disposeBag)
        
        subject
            .debounce(debounce, scheduler: MainScheduler.instance)
            .subscribeNext { [unowned self] in
                self.rotateEventViews()
            }
            .addDisposableTo(disposeBag)
    }
    
    override func layoutSubviews() {
        let oldTimeArrowFrame = timeArrow.frame
        super.layoutSubviews()
        
        addButton.center = CGPointMake(frame.size.width - 10.0, bounds.height / 2.0)
        
        if addButton.superview != nil {
            addButton.hidden = false
            timeArrow.frame.size.width -= 23
            timeArrow.center.y = bounds.height / 2.0
        } else {
            addButton.hidden = true
        }
        
        let newTimeArrowFrame = timeArrow.frame
        
        if oldTimeArrowFrame != newTimeArrowFrame {
            sourceEvents.forEach({ $0.removeBehavior })
            animator?.removeAllBehaviors()
            _needRefreshEventViews = true
        }
        
        if _needRefreshEventViews {
            _needRefreshEventViews = false
            refreshSourceEventsCenters()
        }
    }
    
    func refreshSourceEventsCenters() {
        sourceEvents.forEach {
            $0.center.x = xPositionByTime($0.recorded.time)
            $0.center.y = bounds.height / 2.0
            if let snap = $0.snap {
                snap.snapPoint = $0.center
            }
        }
    }
    
    private func _handleLongPressGestureRecognizer(r: UIGestureRecognizer) {
        let location = r.locationInView(self)
        switch r.state {
        case .Began:
            if let i = sourceEvents.indexOf({ $0.frame.contains(location) }) {
                _panEventView = sourceEvents[i]
            }
            if let panEventView = _panEventView {
                panEventView.animator?.removeBehavior(panEventView.snap!)
                
                _ghostEventView = EventView(recorded: panEventView.recorded)
                _ghostEventView!.center = CGPointMake(xPositionByTime(_ghostEventView!.recorded.time), bounds.height / 2)
                changeGhostColorAndAlpha(_ghostEventView!, recognizer: r)
                addSubview(_ghostEventView!)
                
                sceneView.showTrashView()
            }
        case .Changed:
            if let panEventView = _panEventView {
                let time = timeByXPosition(location.x)
                panEventView.center = CGPointMake(xPositionByTime(time), location.y)
                panEventView.recorded = RecordedType(time: time, event: panEventView.recorded.value)
                
                changeGhostColorAndAlpha(_ghostEventView!, recognizer: r)
                _ghostEventView!.recorded = panEventView.recorded
                _ghostEventView!.center = CGPointMake(xPositionByTime(time), bounds.height / 2)
                sceneView.resultSequence.subject.onNext()
            }
        case .Ended, .Cancelled:
            _ghostEventView?.removeFromSuperview()
            _ghostEventView = nil
            
            if let panEventView = _panEventView {
                animatorAddBehaviorsToPanEventView(panEventView, recognizer: r, resultSequence: sceneView.resultSequence)
                panEventView.superview?.bringSubviewToFront(panEventView)
                let time = timeByXPosition(r.locationInView(self).x)
                panEventView.recorded = RecordedType(time: time, event: panEventView.recorded.value)
            }
            _panEventView = nil
            sceneView.hideTrashView()
            sceneView.resultSequence.subject.onNext()
        default: break
        }
    }
    
    func addEventToTimeline(recorded: RecordedType, animator: UIDynamicAnimator!) {
        let v = EventView(recorded: recorded)
        if editing {
            v.addTapRecognizer()
        }
        addSubview(v)
        v.use(animator, sequence: self)
        sourceEvents.append(v)
    }
    
     func changeGhostColorAndAlpha(ghostEventView: EventView, recognizer: UIGestureRecognizer) {
        if onDeleteZone(recognizer) == true {
            [ghostEventView, sceneView.trashView].forEach(Animation.shake)
            sceneView.trashView.alpha = 0.5
        } else {
            [ghostEventView, sceneView.trashView].forEach(Animation.stopShake)
            sceneView.trashView.alpha = 0.2
        }
        ghostEventView.setGhostColorOnDeleteZone(onDeleteZone(recognizer))
    }
    
    private func animatorAddBehaviorsToPanEventView(panEventView: EventView, recognizer: UIGestureRecognizer, resultSequence: ResultSequenceView) {
        if let animator = panEventView.animator {
            let time = timeByXPosition(recognizer.locationInView(self).x)
            
            if onDeleteZone(recognizer) == true {
                Animation.hideWithCompletion(panEventView) { _ in
                    if let index = self.sourceEvents.indexOf(panEventView) {
                        self.sourceEvents.removeAtIndex(index)
                    }
                }
            } else {
                if let snap = panEventView.snap {
                    snap.snapPoint.x = xPositionByTime(time)
                    snap.snapPoint.y = bounds.height / 2.0
                    animator.addBehavior(snap)
                }
            }
        }
    }
    
    private func onDeleteZone(recognizer: UIGestureRecognizer) -> Bool {
        let trash = sceneView.trashView
        let loc = recognizer.locationInView(superview)
        let eventViewFrame = CGRectMake(loc.x - 19, loc.y - 19, 38, 38)
        if CGRectIntersectsRect(trash.frame, eventViewFrame) {
            return true
        }
        return false
    }
    
    func showAddButton() {
        addSubview(addButton)
        removeGestureRecognizer(longPressGestureRecorgnizer)
    }
    
    func hideAddButton() {
        addButton.removeFromSuperview()
        addGestureRecognizer(longPressGestureRecorgnizer)
    }
    
    func addTapRecognizers() {
        sourceEvents.forEach { $0.addTapRecognizer() }
    }
    
    func removeTapRecognizers() {
        sourceEvents.forEach { $0.removeTapRecognizer() }
    }
    
    func allEventViewsAnimation() {
        sourceEvents.forEach(Animation.scale)
    }
    
    override func setEditing() {
        super.setEditing()
        if editing {
            addTapRecognizers()
            showAddButton()
            addButton.addTarget(self, action: #selector(SourceSequenceView.addEventToTimeline(_:)), forControlEvents: .TouchUpInside)
        } else {
            removeTapRecognizers()
            hideAddButton()
        }
        allEventViewsAnimation()
    }
    
    func addEventToTimeline(sender: UIButton) {
        Notifications.addEvent.post(object: sender)
    }
    
    func rotateEventViews() {
        let sortedEvents = sourceEvents.sort({ $0.recorded.time < $1.recorded.time })
        let sortedEventsRecorded = sortedEvents.map({ $0.recorded })
        let angs = angles(sortedEventsRecorded)
        sortedEvents.forEach({ eventView in
            if let index = sortedEvents.indexOf({ $0 == eventView }) {
                Animation.rotate(eventView, toAngle: angs[index])
            }
        })
    }

//    MARK: UIDynamicAnimatorDelegate methods
    
    func dynamicAnimatorDidPause(animator: UIDynamicAnimator) {
        subject.onNext()
    }
}