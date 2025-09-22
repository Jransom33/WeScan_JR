//
//  TextRectangleDetector.swift
//  WeScan
//
//  Created by AI Assistant on 09/10/2025.
//  Copyright © 2025 WeTransfer. All rights reserved.
//

import CoreImage
import Foundation
import Vision

/// Text-based rectangle detector that uses OCR to find document boundaries
@available(iOS 11.0, *)
enum TextRectangleDetector {
    
    /// Detects document boundaries using text recognition
    /// - Parameters:
    ///   - pixelBuffer: The pixel buffer to analyze
    ///   - completion: Callback with detected rectangle or nil
    static func detectDocumentBounds(
        forPixelBuffer pixelBuffer: CVPixelBuffer,
        completion: @escaping ((Quadrilateral?) -> Void)
    ) {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        // Create text recognition request
        let textRequest = VNRecognizeTextRequest { request, error in
            if let error = error {
                print("📸📸📸 TextDetector: Error recognizing text: \(error)")
                completion(nil)
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation],
                  !observations.isEmpty else {
                print("📸📸📸 TextDetector: No text found")
                completion(nil)
                return
            }
            
            print("📸📸📸 TextDetector: Found \(observations.count) text regions")
            
            // Calculate text-based document boundaries
            let documentRect = calculateDocumentBounds(from: observations, imageSize: CGSize(width: width, height: height))
            completion(documentRect)
        }
        
        // Configure text recognition for optimal performance
        textRequest.recognitionLevel = .fast  // Fast for real-time processing
        if #available(iOS 16.0, *) {
            textRequest.automaticallyDetectsLanguage = true
        }
        textRequest.minimumTextHeight = 0.01  // Detect small text
        
        do {
            try requestHandler.perform([textRequest])
        } catch {
            print("📸📸📸 TextDetector: Failed to perform text recognition: \(error)")
            completion(nil)
        }
    }
    
    /// Calculates document boundaries based on text observations
    private static func calculateDocumentBounds(
        from observations: [VNRecognizedTextObservation],
        imageSize: CGSize
    ) -> Quadrilateral? {
        
        // Filter observations for quality
        let qualityObservations = observations.filter { observation in
            observation.confidence > 0.3  // Minimum confidence threshold
        }
        
        guard qualityObservations.count >= 3 else {
            print("📸📸📸 TextDetector: Insufficient quality text regions (\(qualityObservations.count))")
            return nil
        }
        
        // Extract bounding boxes in image coordinates
        var textBounds: [CGRect] = []
        
        for observation in qualityObservations {
            let boundingBox = observation.boundingBox
            
            // Convert from Vision coordinates (0,0 bottom-left) to UIKit coordinates (0,0 top-left)
            let rect = CGRect(
                x: boundingBox.minX * imageSize.width,
                y: (1.0 - boundingBox.maxY) * imageSize.height,
                width: boundingBox.width * imageSize.width,
                height: boundingBox.height * imageSize.height
            )
            
            textBounds.append(rect)
            
            print("📸📸📸 TextDetector: Text region - x: \(Int(rect.minX)), y: \(Int(rect.minY)), w: \(Int(rect.width)), h: \(Int(rect.height))")
        }
        
        // Calculate overall text content area
        let contentBounds = calculateContentBounds(from: textBounds)
        
        // Apply smart padding to estimate page boundaries
        let documentBounds = applyDocumentPadding(to: contentBounds, imageSize: imageSize)
        
        print("📸📸📸 TextDetector: Content bounds - x: \(Int(contentBounds.minX)), y: \(Int(contentBounds.minY)), w: \(Int(contentBounds.width)), h: \(Int(contentBounds.height))")
        print("📸📸📸 TextDetector: Document bounds - x: \(Int(documentBounds.minX)), y: \(Int(documentBounds.minY)), w: \(Int(documentBounds.width)), h: \(Int(documentBounds.height))")
        
        // Convert to Quadrilateral
        let quad = Quadrilateral(
            topLeft: CGPoint(x: documentBounds.minX, y: documentBounds.minY),
            topRight: CGPoint(x: documentBounds.maxX, y: documentBounds.minY),
            bottomRight: CGPoint(x: documentBounds.maxX, y: documentBounds.maxY),
            bottomLeft: CGPoint(x: documentBounds.minX, y: documentBounds.maxY)
        )
        
        print("📸📸📸 TextDetector: Generated rectangle - area: \(quad.area), aspect ratio: \(quad.aspectRatio)")
        
        return quad
    }
    
    /// Calculates the overall bounds that encompass all text content
    private static func calculateContentBounds(from textBounds: [CGRect]) -> CGRect {
        guard !textBounds.isEmpty else {
            return CGRect.zero
        }
        
        let minX = textBounds.map { $0.minX }.min() ?? 0
        let minY = textBounds.map { $0.minY }.min() ?? 0
        let maxX = textBounds.map { $0.maxX }.max() ?? 0
        let maxY = textBounds.map { $0.maxY }.max() ?? 0
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    /// Applies intelligent padding to estimate document edges from content
    private static func applyDocumentPadding(to contentBounds: CGRect, imageSize: CGSize) -> CGRect {
        // Calculate adaptive padding based on content size and image dimensions
        let contentWidth = contentBounds.width
        let contentHeight = contentBounds.height
        
        // Padding as percentage of content size (with minimum values)
        let horizontalPaddingPercent: CGFloat = 0.15  // 15% padding
        let verticalPaddingPercent: CGFloat = 0.20    // 20% padding
        
        let horizontalPadding = max(contentWidth * horizontalPaddingPercent, 20)
        let verticalPadding = max(contentHeight * verticalPaddingPercent, 30)
        
        // Apply padding while staying within image bounds
        let paddedBounds = CGRect(
            x: max(0, contentBounds.minX - horizontalPadding),
            y: max(0, contentBounds.minY - verticalPadding),
            width: min(imageSize.width - max(0, contentBounds.minX - horizontalPadding), 
                      contentBounds.width + 2 * horizontalPadding),
            height: min(imageSize.height - max(0, contentBounds.minY - verticalPadding), 
                       contentBounds.height + 2 * verticalPadding)
        )
        
        return paddedBounds
    }
}

/// Hybrid detector that combines Vision rectangle detection with text-based detection
@available(iOS 11.0, *)
enum HybridRectangleDetector {
    
    /// Detects rectangles using both CoreML and text-based methods
    static func detectBestRectangle(
        forPixelBuffer pixelBuffer: CVPixelBuffer,
        completion: @escaping ((Quadrilateral?) -> Void)
    ) {
        let group = DispatchGroup()
        var visionResult: Quadrilateral?
        var textResult: Quadrilateral?
        
        // Run CoreML detection
        group.enter()
        CoreMLRectangleDetector.rectangle(forPixelBuffer: pixelBuffer) { result in
            visionResult = result
            group.leave()
        }
        
        // Run text-based detection
        group.enter()
        TextRectangleDetector.detectDocumentBounds(forPixelBuffer: pixelBuffer) { result in
            textResult = result
            group.leave()
        }
        
        // Combine results when both complete
        group.notify(queue: .main) {
            let bestResult = chooseBestResult(vision: visionResult, text: textResult)
            completion(bestResult)
        }
    }
    
    /// Chooses the best result between CoreML and text-based detection
    private static func chooseBestResult(
        vision: Quadrilateral?,
        text: Quadrilateral?
    ) -> Quadrilateral? {
        
        guard let vision = vision, let text = text else {
            print("📸📸📸 HybridDetector: Using fallback - Vision: \(vision != nil), Text: \(text != nil)")
            return vision ?? text
        }
        
        // Calculate quality scores for both results
        let visionScore = calculateQualityScore(for: vision, source: "Vision")
        let textScore = calculateQualityScore(for: text, source: "Text")
        
        print("📸📸📸 HybridDetector: Vision score: \(String(format: "%.2f", visionScore)), Text score: \(String(format: "%.2f", textScore))")
        
        // Prefer text-based result if it has significantly higher quality
        if textScore > visionScore + 0.1 {  // 0.1 bias towards text detection
            print("📸📸📸 HybridDetector: Selected TEXT-based result")
            return text
        } else {
            print("📸📸📸 HybridDetector: Selected VISION-based result")
            return vision
        }
    }
    
    /// Calculates a quality score for a detected rectangle
    private static func calculateQualityScore(for quad: Quadrilateral, source: String) -> Double {
        let area = quad.area
        let aspectRatio = quad.aspectRatio
        
        // Size score (normalized to typical page size)
        let sizeScore = min(area / 800000.0, 1.0)
        
        // Aspect ratio score (prefer document-like ratios)
        let aspectRatioScore: Double
        if aspectRatio >= 0.6 && aspectRatio <= 1.7 {
            aspectRatioScore = 1.0 - abs(aspectRatio - 0.75) / 0.75
        } else {
            aspectRatioScore = 0.3
        }
        
        // Combined score
        let qualityScore = (sizeScore * 0.6) + (aspectRatioScore * 0.4)
        
        print("📸📸📸 HybridDetector: \(source) - Area: \(Int(area)), AspectRatio: \(String(format: "%.2f", aspectRatio)), Score: \(String(format: "%.2f", qualityScore))")
        
        return qualityScore
    }
}
