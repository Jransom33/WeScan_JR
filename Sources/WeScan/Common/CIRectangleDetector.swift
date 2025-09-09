//
//  RectangleDetector.swift
//  WeScan
//
//  Created by Boris Emorine on 2/13/18.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import AVFoundation
import CoreImage
import Foundation

/// Class used to detect rectangles from an image.
enum CIRectangleDetector {

    static let rectangleDetector = CIDetector(ofType: CIDetectorTypeRectangle,
                                              context: CIContext(options: nil),
                                              options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])

    /// Detects rectangles from the given image on iOS 10.
    ///
    /// - Parameters:
    ///   - image: The image to detect rectangles on.
    /// - Returns: The biggest detected rectangle on the image.
    static func rectangle(forImage image: CIImage, completion: @escaping ((Quadrilateral?) -> Void)) {
        let biggestRectangle = rectangle(forImage: image)
        completion(biggestRectangle)
    }

    static func rectangle(forImage image: CIImage) -> Quadrilateral? {
        guard let rectangleFeatures = rectangleDetector?.features(in: image) as? [CIRectangleFeature] else {
            print("📸📸📸 CIDetector: No rectangle features found")
            return nil
        }
        
        print("📸📸📸 CIDetector: Found \(rectangleFeatures.count) raw rectangles")

        let quads = rectangleFeatures.map { rectangle in
            return Quadrilateral(rectangleFeature: rectangle)
        }
        
        for (index, quad) in quads.enumerated() {
            print("📸📸📸 CIDetector: Rectangle \(index + 1) - area: \(quad.area), aspect ratio: \(quad.aspectRatio)")
        }
        
        let bestQuad = quads.biggest()
        if let best = bestQuad {
            print("📸📸📸 CIDetector: Selected best rectangle with area: \(best.area), aspect ratio: \(best.aspectRatio)")
        } else {
            print("📸📸📸 CIDetector: No best rectangle selected")
        }

        return bestQuad
    }
}
