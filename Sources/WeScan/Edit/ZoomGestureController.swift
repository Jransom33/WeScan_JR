//
//  ZoomGestureController.swift
//  WeScan
//
//  Created by Bobo on 5/31/18.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import AVFoundation
import Foundation
import UIKit

final class ZoomGestureController {

    private let image: UIImage
    private let quadView: QuadrilateralView
    private var previousPanPosition: CGPoint?
    private var closestCorner: CornerPosition?

    init(image: UIImage, quadView: QuadrilateralView) {
        self.image = image
        self.quadView = quadView
    }

    @objc func handle(pan: UIGestureRecognizer) {
        guard let drawnQuad = quadView.quad else {
            return
        }

        guard pan.state != .ended else {
            if let corner = self.closestCorner {
                print("📸📸📸 CornerEdit: Finished adjusting \(corner) corner")
                print("📸📸📸 CornerEdit: Final rectangle - TL(\(String(format: "%.1f", drawnQuad.topLeft.x)), \(String(format: "%.1f", drawnQuad.topLeft.y))) TR(\(String(format: "%.1f", drawnQuad.topRight.x)), \(String(format: "%.1f", drawnQuad.topRight.y))) BR(\(String(format: "%.1f", drawnQuad.bottomRight.x)), \(String(format: "%.1f", drawnQuad.bottomRight.y))) BL(\(String(format: "%.1f", drawnQuad.bottomLeft.x)), \(String(format: "%.1f", drawnQuad.bottomLeft.y)))")
            }
            self.previousPanPosition = nil
            self.closestCorner = nil
            quadView.resetHighlightedCornerViews()
            return
        }

        let position = pan.location(in: quadView)

        let previousPanPosition = self.previousPanPosition ?? position
        let closestCorner = self.closestCorner ?? position.closestCornerFrom(quad: drawnQuad)
        
        // Log when starting to adjust a corner
        if self.closestCorner == nil {
            print("📸📸📸 CornerEdit: Started adjusting \(closestCorner) corner")
            print("📸📸📸 CornerEdit: Original rectangle - TL(\(String(format: "%.1f", drawnQuad.topLeft.x)), \(String(format: "%.1f", drawnQuad.topLeft.y))) TR(\(String(format: "%.1f", drawnQuad.topRight.x)), \(String(format: "%.1f", drawnQuad.topRight.y))) BR(\(String(format: "%.1f", drawnQuad.bottomRight.x)), \(String(format: "%.1f", drawnQuad.bottomRight.y))) BL(\(String(format: "%.1f", drawnQuad.bottomLeft.x)), \(String(format: "%.1f", drawnQuad.bottomLeft.y)))")
        }

        let offset = CGAffineTransform(translationX: position.x - previousPanPosition.x, y: position.y - previousPanPosition.y)
        let cornerView = quadView.cornerViewForCornerPosition(position: closestCorner)
        let draggedCornerViewCenter = cornerView.center.applying(offset)

        quadView.moveCorner(cornerView: cornerView, atPoint: draggedCornerViewCenter)

        self.previousPanPosition = position
        self.closestCorner = closestCorner

        let scale = image.size.width / quadView.bounds.size.width
        let scaledDraggedCornerViewCenter = CGPoint(x: draggedCornerViewCenter.x * scale, y: draggedCornerViewCenter.y * scale)
        guard let zoomedImage = image.scaledImage(
            atPoint: scaledDraggedCornerViewCenter,
            scaleFactor: 2.5,
            targetSize: quadView.bounds.size
        ) else {
            return
        }

        quadView.highlightCornerAtPosition(position: closestCorner, with: zoomedImage)
    }

}
