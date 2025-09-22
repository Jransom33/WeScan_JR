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
        
        let params = LetterboxParameters(scale: scale, padX: padX, padY: padY)
        
        print("📸📸📸 CoreMLDetector: Letterbox parameters:")
        print("📸📸📸 CoreMLDetector:   Original size: \(originalSize)")
        print("📸📸📸 CoreMLDetector:   Target size: \(targetSize)")
        print("📸📸📸 CoreMLDetector:   Scale: \(scale)")
        print("📸📸📸 CoreMLDetector:   Scaled size: (\(scaledWidth), \(scaledHeight))")
        print("📸📸📸 CoreMLDetector:   Padding: (\(padX), \(padY))")
        
        return params
    }
    
    /// Decode heatmaps to find corner points in 320x320 space
    private static func decodeHeatmaps(_ heatmaps: MLMultiArray, stride: Int = 4) -> [CGPoint] {
        let shape = heatmaps.shape.map { Int(truncating: $0) }
        let hasBatch = shape.count == 4
        let channels = hasBatch ? shape[1] : shape[0]
        let height = hasBatch ? shape[2] : shape[1]
        let width = hasBatch ? shape[3] : shape[2]

        print("📸📸📸 CoreMLDetector: Heatmap details:")
        print("📸📸📸 CoreMLDetector:   dataType: \(heatmaps.dataType.rawValue)")
        print("📸📸📸 CoreMLDetector:   shape: \(shape)")
        print("📸📸📸 CoreMLDetector:   strides: \(heatmaps.strides)")
        print("📸📸📸 CoreMLDetector:   hasBatch: \(hasBatch), channels: \(channels), h: \(height), w: \(width)")

        guard channels == 4 else {
            print("📸📸📸 CoreMLDetector: ❌ Expected 4 channels, got \(channels)")
            return []
        }
        guard height == 80 && width == 80 else {
            print("📸📸📸 CoreMLDetector: ❌ Expected 80x80 heatmaps, got \(height)x\(width)")
            return []
        }

        // Read values safely based on data type
        var values = [Float](repeating: 0, count: heatmaps.count)
        switch heatmaps.dataType {
        case .float32:
            let ptr = heatmaps.dataPointer.assumingMemoryBound(to: Float32.self)
            values.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress!.assign(from: ptr, count: heatmaps.count)
            }
        case .double:
            let ptr = heatmaps.dataPointer.assumingMemoryBound(to: Double.self)
            for i in 0..<heatmaps.count {
                values[i] = Float(ptr[i])
            }
        default:
            // Safe but slower fallback for any data type
            for i in 0..<heatmaps.count {
                values[i] = heatmaps[i].floatValue
            }
        }

        // Index function to handle batch dimension
        func index(_ c: Int, _ y: Int, _ x: Int) -> Int {
            if hasBatch {
                return ((0 * channels + c) * height + y) * width + x
            } else {
                return (c * height + y) * width + x
            }
        }

        var points: [CGPoint] = []
        
        // Find peak in each channel (corner)
        for channel in 0..<channels {
            var maxValue: Float = -Float.infinity
            var maxY = 0
            var maxX = 0
            
            // Track top 5 values for debugging
            var topValues: [(value: Float, x: Int, y: Int)] = []
            
            for y in 0..<height {
                for x in 0..<width {
                    let idx = index(channel, y, x)
                    let value = values[idx]
                    if value > maxValue {
                        maxValue = value
                        maxY = y
                        maxX = x
                    }
                    
                    // Keep track of top values for debugging
                    topValues.append((value: value, x: x, y: y))
                    topValues.sort { $0.value > $1.value }
                    if topValues.count > 5 {
                        topValues.removeLast()
                    }
                }
            }
            
            print("📸📸📸 CoreMLDetector: Channel \(channel) peak at (\(maxX), \(maxY)) = \(maxValue)")
            
            // Log top 5 values for debugging
            print("📸📸📸 CoreMLDetector: Channel \(channel) top 5 values:")
            for (i, top) in topValues.enumerated() {
                print("📸📸📸 CoreMLDetector:   #\(i+1): (\(top.x), \(top.y)) = \(top.value)")
            }
            
            // Calculate statistics for this channel
            let channelValues = (0..<height).flatMap { y in
                (0..<width).map { x in values[index(channel, y, x)] }
            }
            let minVal = channelValues.min() ?? 0
            let maxVal = channelValues.max() ?? 0
            let meanVal = channelValues.reduce(0, +) / Float(channelValues.count)
            let variance = channelValues.map { pow($0 - meanVal, 2) }.reduce(0, +) / Float(channelValues.count)
            let stdDev = sqrt(variance)
            
            print("📸📸📸 CoreMLDetector: Channel \(channel) stats - min: \(minVal), max: \(maxVal), mean: \(meanVal), std: \(stdDev)")
            
            // Map to 320x320 space using stride
            let point = CGPoint(x: CGFloat(maxX * stride), y: CGFloat(maxY * stride))
            points.append(point)
        }
        
        return points
    }
    
    /// Map points from 320x320 space back to original image coordinates
    private static func unletterbox(points320: [CGPoint], letterbox: LetterboxParameters) -> [CGPoint] {
        print("📸📸📸 CoreMLDetector: Unletterboxing points:")
        print("📸📸📸 CoreMLDetector:   Input points (320x320 space): \(points320)")
        
        let originalPoints = points320.map { point in
            let originalX = (point.x - letterbox.padX) / letterbox.scale
            let originalY = (point.y - letterbox.padY) / letterbox.scale
            
            print("📸📸📸 CoreMLDetector:   (\(point.x), \(point.y)) -> (\(originalX), \(originalY))")
            
            return CGPoint(x: originalX, y: originalY)
        }
        
        print("📸📸📸 CoreMLDetector:   Output points (original space): \(originalPoints)")
        
        return originalPoints
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
