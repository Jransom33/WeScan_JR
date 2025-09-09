//
//  Array+Utils.swift
//  WeScan
//
//  Created by Boris Emorine on 2/8/18.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import Foundation
import Vision

extension Array where Element == Quadrilateral {

    /// Finds the best rectangle within an array of `Quadrilateral` objects.
    /// Prioritizes rectangles that are more likely to be full document pages
    /// by considering both size and aspect ratio.
    func biggest() -> Quadrilateral? {
        guard !isEmpty else { return nil }
        
        let bestRectangle = self.max(by: { rect1, rect2 -> Bool in
            let score1 = documentScore(for: rect1)
            let score2 = documentScore(for: rect2)
            return score1 < score2
        })

        return bestRectangle
    }
    
    /// Calculates a score for how likely a rectangle is to represent a document page.
    /// Higher scores indicate better document candidates.
    private func documentScore(for quad: Quadrilateral) -> Double {
        let area = quad.area
        let aspectRatio = quad.aspectRatio
        
        // Prefer larger rectangles (area component)
        let areaScore = area
        
        // Prefer aspect ratios closer to typical document ratios (0.7-1.4)
        // US Letter: ~0.77, A4: ~0.71, Square: 1.0
        let idealAspectRatio = 0.75
        let aspectRatioDifference = abs(aspectRatio - idealAspectRatio)
        let aspectRatioScore = Swift.max(0, 1.0 - aspectRatioDifference * 2.0) // Penalty for extreme ratios
        
        // Combined score: heavily weight area, but give bonus for good aspect ratio
        return areaScore * (0.7 + 0.3 * aspectRatioScore)
    }

}
