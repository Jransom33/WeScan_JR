//
//  CoreMLRectangleDetector.swift
//  WeScan
//
//  Created by AI Assistant.
//  Copyright © 2025 WeTransfer. All rights reserved.
//

import CoreImage
import CoreML
import Foundation
import Vision
import UIKit

/// Letterbox parameters for image preprocessing
struct LetterboxParameters {
    let scale: CGFloat
    let padX: CGFloat
    let padY: CGFloat
}

/// CoreML-based rectangle detector using trained corner keypoint model
@available(iOS 11.0, *)
enum CoreMLRectangleDetector {
    
    private static var visionModel: VNCoreMLModel?
    
    /// Configure the CoreML model for corner detection
    /// - Parameter model: The CoreML model to use for corner detection
    static func configure(with model: MLModel) throws {
        let visionMLModel = try VNCoreMLModel(for: model)
        self.visionModel = visionMLModel
        print("📸📸📸 CoreMLDetector: Successfully configured with provided CoreML model")
    }
    
    /// Convenience method to configure with a model from bundle
    /// - Parameters:
    ///   - modelName: Name of the model file (without extension)
    ///   - bundle: Bundle containing the model (defaults to main bundle)
    static func configure(modelName: String, in bundle: Bundle = Bundle.main) throws {
        guard let modelURL = bundle.url(forResource: modelName, withExtension: "mlpackage") else {
            throw NSError(domain: "CoreMLRectangleDetector", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "CoreML model '\(modelName).mlpackage' not found in bundle"
            ])
        }
        
        let model = try MLModel(contentsOf: modelURL)
        try configure(with: model)
    }
    
    /// Check if a CoreML model has been configured
    static var isConfigured: Bool {
        return visionModel != nil
    }
    
    /// Get the configured model (if any)
    private static func getConfiguredModel() -> VNCoreMLModel? {
        guard let model = visionModel else {
            print("📸📸📸 CoreMLDetector: ❌ CRITICAL ERROR: No CoreML model configured!")
            print("📸📸📸 CoreMLDetector: ")
            print("📸📸📸 CoreMLDetector: 🚨 You must configure a CoreML model before using WeScan")
            print("📸📸📸 CoreMLDetector: ")
            print("📸📸📸 CoreMLDetector: 💡 Solution:")
            print("📸📸📸 CoreMLDetector:    1. Load your trained CoreML model:")
            print("📸📸📸 CoreMLDetector:       guard let modelURL = Bundle.main.url(forResource: \"YourModel\", withExtension: \"mlpackage\") else { return }")
            print("📸📸📸 CoreMLDetector:       let model = try MLModel(contentsOf: modelURL)")
            print("📸📸📸 CoreMLDetector: ")
            print("📸📸📸 CoreMLDetector:    2. Configure WeScan before using:")
            print("📸📸📸 CoreMLDetector:       try CoreMLRectangleDetector.configure(with: model)")
            print("📸📸📸 CoreMLDetector: ")
            print("📸📸📸 CoreMLDetector:    3. Then instantiate your scanner:")
            print("📸📸📸 CoreMLDetector:       let scanner = ImageScannerController()")
            print("📸📸📸 CoreMLDetector: ")
            print("📸📸📸 CoreMLDetector: ⚠️  Document detection will not work without model configuration!")
            return nil
        }
        return model
    }
    
    /// Calculate letterbox parameters for 320x320 input while preserving aspect ratio
    private static func letterboxParameters(originalSize: CGSize, targetSize: CGFloat = 320) -> LetterboxParameters {
        let scale = min(targetSize / originalSize.width, targetSize / originalSize.height)
        let scaledWidth = round(originalSize.width * scale)
        let scaledHeight = round(originalSize.height * scale)
        let padX = (targetSize - scaledWidth) / 2.0
        let padY = (targetSize - scaledHeight) / 2.0
        
        return LetterboxParameters(scale: scale, padX: padX, padY: padY)
    }
    
    /// Decode heatmaps to find corner points in 320x320 space
    private static func decodeHeatmaps(_ heatmaps: MLMultiArray, stride: Int = 4) -> [CGPoint] {
        guard heatmaps.count >= 4 * 80 * 80 else {
            print("📸📸📸 CoreMLDetector: Unexpected heatmap size")
            return []
        }
        
        let channels = 4
        let height = 80
        let width = 80
        var points: [CGPoint] = []
        
        // Get pointer to the data
        let dataPointer = UnsafeMutablePointer<Double>(OpaquePointer(heatmaps.dataPointer))
        let countPerMap = height * width
        
        for channel in 0..<channels {
            let baseIndex = channel * countPerMap
            var maxIndex = 0
            var maxValue = -Double.infinity
            
            // Find the maximum value in this channel
            for i in 0..<countPerMap {
                let value = dataPointer[baseIndex + i]
                if value > maxValue {
                    maxValue = value
                    maxIndex = i
                }
            }
            
            // Convert linear index to 2D coordinates
            let y = maxIndex / width
            let x = maxIndex % width
            
            // Map to 320x320 space using stride
            let point = CGPoint(x: CGFloat(x * stride), y: CGFloat(y * stride))
            points.append(point)
        }
        
        return points
    }
    
    /// Map points from 320x320 space back to original image coordinates
    private static func unletterbox(points320: [CGPoint], letterbox: LetterboxParameters) -> [CGPoint] {
        return points320.map { point in
            CGPoint(
                x: (point.x - letterbox.padX) / letterbox.scale,
                y: (point.y - letterbox.padY) / letterbox.scale
            )
        }
    }
    
    /// Convert corner points to a Quadrilateral
    /// The model outputs corners in order: Top-Left, Top-Right, Bottom-Right, Bottom-Left
    private static func pointsToQuadrilateral(points: [CGPoint]) -> Quadrilateral? {
        guard points.count == 4 else {
            print("📸📸📸 CoreMLDetector: Expected 4 points, got \(points.count)")
            return nil
        }
        
        return Quadrilateral(
            topLeft: points[0],      // Top-Left
            topRight: points[1],     // Top-Right
            bottomRight: points[2],  // Bottom-Right
            bottomLeft: points[3]    // Bottom-Left
        )
    }
    
    /// Main function to detect rectangle using CoreML model
    private static func detectRectangle(
        for request: VNImageRequestHandler,
        width: CGFloat,
        height: CGFloat,
        completion: @escaping ((Quadrilateral?) -> Void)
    ) {
        guard let visionModel = getConfiguredModel() else {
            completion(nil)
            return
        }
        
        // Calculate letterbox parameters
        let originalSize = CGSize(width: width, height: height)
        let letterbox = letterboxParameters(originalSize: originalSize)
        
        // Create CoreML request
        let coreMLRequest = VNCoreMLRequest(model: visionModel) { request, error in
            if let error = error {
                print("📸📸📸 CoreMLDetector: CoreML request failed: \(error)")
                completion(nil)
                return
            }
            
            guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                  let firstResult = results.first,
                  let heatmaps = firstResult.featureValue.multiArrayValue else {
                print("📸📸📸 CoreMLDetector: No valid results from CoreML model")
                completion(nil)
                return
            }
            
            print("📸📸📸 CoreMLDetector: Received heatmaps with shape: \(heatmaps.shape)")
            
            // Decode heatmaps to get corner points in 320x320 space
            let points320 = decodeHeatmaps(heatmaps)
            
            if points320.count != 4 {
                print("📸📸📸 CoreMLDetector: Failed to decode 4 corner points")
                completion(nil)
                return
            }
            
            // Map points back to original image coordinates
            let originalPoints = unletterbox(points320: points320, letterbox: letterbox)
            
            // Convert to Quadrilateral
            guard let quadrilateral = pointsToQuadrilateral(points: originalPoints) else {
                print("📸📸📸 CoreMLDetector: Failed to create quadrilateral")
                completion(nil)
                return
            }
            
            print("📸📸📸 CoreMLDetector: Successfully detected corners:")
            print("  Top-Left: \(quadrilateral.topLeft)")
            print("  Top-Right: \(quadrilateral.topRight)")
            print("  Bottom-Right: \(quadrilateral.bottomRight)")
            print("  Bottom-Left: \(quadrilateral.bottomLeft)")
            print("  Area: \(quadrilateral.area)")
            print("  Aspect Ratio: \(quadrilateral.aspectRatio)")
            
            completion(quadrilateral)
        }
        
        // Use scaleFit to maintain aspect ratio (letterboxing)
        coreMLRequest.imageCropAndScaleOption = .scaleFit
        
        // Perform the request
        do {
            try request.perform([coreMLRequest])
        } catch {
            print("📸📸📸 CoreMLDetector: Failed to perform request: \(error)")
            completion(nil)
        }
    }
    
    /// Detects rectangles from the given CVPixelBuffer using CoreML
    ///
    /// - Parameters:
    ///   - pixelBuffer: The pixelBuffer to detect rectangles on.
    ///   - completion: The detected rectangle on the CVPixelBuffer
    static func rectangle(forPixelBuffer pixelBuffer: CVPixelBuffer, completion: @escaping ((Quadrilateral?) -> Void)) {
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        detectRectangle(
            for: imageRequestHandler,
            width: CGFloat(CVPixelBufferGetWidth(pixelBuffer)),
            height: CGFloat(CVPixelBufferGetHeight(pixelBuffer)),
            completion: completion
        )
    }
    
    /// Detects rectangles from the given image using CoreML
    ///
    /// - Parameters:
    ///   - image: The image to detect rectangles on.
    ///   - completion: The detected rectangle on the image.
    static func rectangle(forImage image: CIImage, completion: @escaping ((Quadrilateral?) -> Void)) {
        let imageRequestHandler = VNImageRequestHandler(ciImage: image, options: [:])
        detectRectangle(
            for: imageRequestHandler,
            width: image.extent.width,
            height: image.extent.height,
            completion: completion
        )
    }
    
    /// Detects rectangles from the given image with orientation using CoreML
    ///
    /// - Parameters:
    ///   - image: The image to detect rectangles on.
    ///   - orientation: The orientation of the image.
    ///   - completion: The detected rectangle on the image.
    static func rectangle(
        forImage image: CIImage,
        orientation: CGImagePropertyOrientation,
        completion: @escaping ((Quadrilateral?) -> Void)
    ) {
        let imageRequestHandler = VNImageRequestHandler(ciImage: image, orientation: orientation, options: [:])
        let orientedImage = image.oriented(orientation)
        detectRectangle(
            for: imageRequestHandler,
            width: orientedImage.extent.width,
            height: orientedImage.extent.height,
            completion: completion
        )
    }
}
