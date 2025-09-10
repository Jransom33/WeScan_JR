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
        
        // Calculate rectangle properties for full-page detection
        let rectangularityScore = calculateRectangularityScore(for: quad)
        let sizeScore = calculateSizeScore(for: quad, referenceArea: maxArea)
        let aspectRatioScore = calculateAspectRatioScore(for: aspectRatio)
        let angleScore = calculateAngleScore(for: quad)
        
        // Heavily prioritize rectangularity and size for full page detection
        let finalScore = sizeScore * 0.4 + rectangularityScore * 0.3 + aspectRatioScore * 0.2 + angleScore * 0.1
        
        print("📸📸📸 RectScoring: Area: \(String(format: "%.0f", area)), AspectRatio: \(String(format: "%.2f", aspectRatio)), Size: \(String(format: "%.2f", sizeScore)), Rectangularity: \(String(format: "%.2f", rectangularityScore)), Angle: \(String(format: "%.2f", angleScore)), FinalScore: \(String(format: "%.2f", finalScore))")
        
        return finalScore
    }
    
    /// Maximum area among all rectangles (for relative size scoring)
    private var maxArea: Double {
        return self.map { $0.area }.max() ?? 1.0
    }
    
    /// Calculates how rectangular/square the quadrilateral is (vs trapezoid/skewed)
    private func calculateRectangularityScore(for quad: Quadrilateral) -> Double {
        // Calculate side lengths
        let topSide = quad.topLeft.distanceTo(point: quad.topRight)
        let rightSide = quad.topRight.distanceTo(point: quad.bottomRight)
        let bottomSide = quad.bottomRight.distanceTo(point: quad.bottomLeft)
        let leftSide = quad.bottomLeft.distanceTo(point: quad.topLeft)
        
        // Check if opposite sides are similar (rectangular property)
        let horizontalSimilarity = 1.0 - abs(topSide - bottomSide) / Swift.max(topSide, bottomSide)
        let verticalSimilarity = 1.0 - abs(leftSide - rightSide) / Swift.max(leftSide, rightSide)
        
        // Penalize heavily skewed shapes (like trapezoids)
        let rectangularityScore = (horizontalSimilarity + verticalSimilarity) / 2.0
        
        return Swift.max(0, rectangularityScore)
    }
    
    /// Calculates size score relative to the largest detected rectangle
    private func calculateSizeScore(for quad: Quadrilateral, referenceArea: Double) -> Double {
        return quad.area / referenceArea
    }
    
    /// Calculates aspect ratio score favoring document-like proportions
    private func calculateAspectRatioScore(for aspectRatio: Double) -> Double {
        // Prefer aspect ratios closer to typical document ratios (0.65-1.5)
        // US Letter: ~0.77, A4: ~0.71, Square: 1.0
        let idealRange = 0.65...1.5
        
        if idealRange.contains(aspectRatio) {
            let idealAspectRatio = 0.75
            let difference = abs(aspectRatio - idealAspectRatio)
            return Swift.max(0, 1.0 - difference * 1.5)
        } else {
            // Heavy penalty for extreme aspect ratios
            return 0.1
        }
    }
    
    /// Calculates angle score to penalize severely angled/slanted rectangles  
    private func calculateAngleScore(for quad: Quadrilateral) -> Double {
        // Calculate approximate angles at corners to detect skewed rectangles
        let angle1 = approximateAngle(from: quad.topLeft, to: quad.topRight, to: quad.bottomRight)
        let angle2 = approximateAngle(from: quad.topRight, to: quad.bottomRight, to: quad.bottomLeft)
        let angle3 = approximateAngle(from: quad.bottomRight, to: quad.bottomLeft, to: quad.topLeft)
        let angle4 = approximateAngle(from: quad.bottomLeft, to: quad.topLeft, to: quad.topRight)
        
        // Calculate how close each angle is to 90 degrees (π/2 radians)
        let idealAngle = Double.pi / 2
        let angleDeviations = [angle1, angle2, angle3, angle4].map { abs($0 - idealAngle) }
        let avgDeviation = angleDeviations.reduce(0, +) / 4.0
        
        // Score based on how close to rectangular angles (lower deviation = higher score)
        let angleScore = Swift.max(0, 1.0 - (avgDeviation / (Double.pi / 4))) // Normalize by 45°
        
        return angleScore
    }
    
    /// Approximates angle between three points
    private func approximateAngle(from p1: CGPoint, to p2: CGPoint, to p3: CGPoint) -> Double {
        let v1 = CGPoint(x: p1.x - p2.x, y: p1.y - p2.y)
        let v2 = CGPoint(x: p3.x - p2.x, y: p3.y - p2.y)
        
        let dot = v1.x * v2.x + v1.y * v2.y
        let mag1 = sqrt(v1.x * v1.x + v1.y * v1.y)
        let mag2 = sqrt(v2.x * v2.x + v2.y * v2.y)
        
        guard mag1 > 0 && mag2 > 0 else { return 0 }
        
        let cosAngle = dot / (mag1 * mag2)
        let clampedCos = Swift.max(-1.0, Swift.min(1.0, Double(cosAngle)))
        return acos(clampedCos)
    }

}
