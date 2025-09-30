//
//  CoreMLSegmentationDetector.swift
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

/// Configuration for CoreML page segmentation
public struct CoreMLSegmentationConfig {
    /// Threshold for converting probabilities to binary mask (default: 0.5)
    public let threshold: Float
    
    /// Minimum contour area to consider as valid page (in 320x320 space)
    public let minContourArea: Float
    
    /// Whether to apply morphological operations to clean up the mask
    public let applyMorphology: Bool
    
    /// Default configuration
    public static let `default` = CoreMLSegmentationConfig(
        threshold: 0.5,
        minContourArea: 1000.0,
        applyMorphology: true
    )
    
    /// Initialize a new configuration
    /// - Parameters:
    ///   - threshold: Threshold for converting probabilities to binary mask
    ///   - minContourArea: Minimum contour area to consider as valid page
    ///   - applyMorphology: Whether to apply morphological operations to clean up the mask
    public init(threshold: Float, minContourArea: Float, applyMorphology: Bool) {
        self.threshold = threshold
        self.minContourArea = minContourArea
        self.applyMorphology = applyMorphology
    }
}

/// Result of page segmentation
public struct PageSegmentationResult {
    /// Binary mask indicating page pixels (1.0) vs background (0.0)
    public let mask: [[Float]]
    
    /// Bounding box of the detected page in original image coordinates
    public let boundingBox: CGRect
    
    /// Confidence score of the segmentation (average probability of page pixels)
    public let confidence: Float
    
    /// Contour points of the page boundary in original image coordinates
    public let contourPoints: [CGPoint]
}

/// CoreML-based page segmentation detector using trained DeepLabV3 model
@available(iOS 15.0, *)
enum CoreMLSegmentationDetector {
    
    private static var visionModel: VNCoreMLModel?
    private static var config: CoreMLSegmentationConfig = .default
    
    /// Configure the CoreML segmentation model
    /// - Parameters:
    ///   - model: The CoreML DeepLabV3 model to use for page segmentation
    ///   - config: Segmentation configuration including thresholds
    static func configure(with model: MLModel, config: CoreMLSegmentationConfig = .default) throws {
        let visionMLModel = try VNCoreMLModel(for: model)
        self.visionModel = visionMLModel
        self.config = config
        print("🎭🎭🎭 SegmentationDetector: Successfully configured with provided CoreML model")
        print("🎭🎭🎭 SegmentationDetector: Threshold: \(config.threshold)")
        print("🎭🎭🎭 SegmentationDetector: Min contour area: \(config.minContourArea)")
        print("🎭🎭🎭 SegmentationDetector: Apply morphology: \(config.applyMorphology)")
    }
    
    /// Convenience method to configure with a model from bundle
    /// - Parameters:
    ///   - modelName: Name of the model file (without extension)
    ///   - bundle: Bundle containing the model (defaults to main bundle)
    ///   - config: Segmentation configuration including thresholds
    static func configure(modelName: String, in bundle: Bundle = Bundle.main, config: CoreMLSegmentationConfig = .default) throws {
        guard let modelURL = bundle.url(forResource: modelName, withExtension: "mlpackage") else {
            throw NSError(domain: "CoreMLSegmentationDetector", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "CoreML segmentation model '\(modelName).mlpackage' not found in bundle"
            ])
        }
        
        let model = try MLModel(contentsOf: modelURL)
        try configure(with: model, config: config)
    }
    
    /// Check if a CoreML segmentation model has been configured
    static var isConfigured: Bool {
        return visionModel != nil
    }
    
    /// Get the configured model (if any)
    private static func getConfiguredModel() -> VNCoreMLModel? {
        guard let model = visionModel else {
            print("🎭🎭🎭 SegmentationDetector: ❌ CRITICAL ERROR: No CoreML segmentation model configured!")
            print("🎭🎭🎭 SegmentationDetector: ")
            print("🎭🎭🎭 SegmentationDetector: 🚨 You must configure a DeepLabV3 segmentation model for page detection")
            print("🎭🎭🎭 SegmentationDetector: ")
            print("🎭🎭🎭 SegmentationDetector: 💡 Solution:")
            print("🎭🎭🎭 SegmentationDetector:    1. Load your trained DeepLabV3 model:")
            print("🎭🎭🎭 SegmentationDetector:       guard let modelURL = Bundle.main.url(forResource: \"DeepLabV3PageSegmentation\", withExtension: \"mlpackage\") else { return }")
            print("🎭🎭🎭 SegmentationDetector:       let model = try MLModel(contentsOf: modelURL)")
            print("🎭🎭🎭 SegmentationDetector: ")
            print("🎭🎭🎭 SegmentationDetector:    2. Configure WeScan before using:")
            print("🎭🎭🎭 SegmentationDetector:       try CoreMLSegmentationDetector.configure(with: model)")
            print("🎭🎭🎭 SegmentationDetector: ")
            print("🎭🎭🎭 SegmentationDetector: ⚠️  Page segmentation will not work without model configuration!")
            return nil
        }
        return model
    }
    
    /// Apply softmax to logits to get probabilities
    private static func applySoftmax(to logits: MLMultiArray) -> MLMultiArray? {
        let shape = logits.shape.map { Int(truncating: $0) }
        guard shape.count == 4, shape[1] == 2 else {
            print("🎭🎭🎭 SegmentationDetector: ❌ Expected shape [1, 2, H, W], got \(shape)")
            return nil
        }
        
        let batch = shape[0]
        let classes = shape[1]
        let height = shape[2]
        let width = shape[3]
        
        // Create output array for probabilities
        guard let probabilities = try? MLMultiArray(shape: logits.shape, dataType: .float32) else {
            print("🎭🎭🎭 SegmentationDetector: ❌ Failed to create probabilities array")
            return nil
        }
        
        // Apply softmax per pixel
        for b in 0..<batch {
            for h in 0..<height {
                for w in 0..<width {
                    // Get logits for both classes at this pixel
                    let bgLogit = logits[[b, 0, h, w] as [NSNumber]].floatValue
                    let pageLogit = logits[[b, 1, h, w] as [NSNumber]].floatValue
                    
                    // Apply softmax
                    let maxLogit = max(bgLogit, pageLogit)
                    let expBg = exp(bgLogit - maxLogit)
                    let expPage = exp(pageLogit - maxLogit)
                    let sum = expBg + expPage
                    
                    let probBg = expBg / sum
                    let probPage = expPage / sum
                    
                    // Store probabilities
                    probabilities[[b, 0, h, w] as [NSNumber]] = NSNumber(value: probBg)
                    probabilities[[b, 1, h, w] as [NSNumber]] = NSNumber(value: probPage)
                }
            }
        }
        
        return probabilities
    }
    
    /// Convert probabilities to binary mask
    private static func createBinaryMask(from probabilities: MLMultiArray, threshold: Float) -> [[Float]] {
        let shape = probabilities.shape.map { Int(truncating: $0) }
        let height = shape[2]
        let width = shape[3]
        
        var mask = Array(repeating: Array(repeating: Float(0.0), count: width), count: height)
        
        print("🎭🎭🎭 SegmentationDetector: Creating binary mask with threshold \(threshold)")
        var pagePixelCount = 0
        var totalPixels = 0
        
        for h in 0..<height {
            for w in 0..<width {
                let pageProb = probabilities[[0, 1, h, w] as [NSNumber]].floatValue
                totalPixels += 1
                
                if pageProb > threshold {
                    mask[h][w] = 1.0
                    pagePixelCount += 1
                }
            }
        }
        
        let pageRatio = Float(pagePixelCount) / Float(totalPixels)
        print("🎭🎭🎭 SegmentationDetector: Page pixels: \(pagePixelCount)/\(totalPixels) (\(String(format: "%.1f", pageRatio * 100))%)")
        
        return mask
    }
    
    /// Find contour points from binary mask
    private static func findContourPoints(from mask: [[Float]]) -> [CGPoint] {
        let height = mask.count
        let width = mask[0].count
        var contourPoints: [CGPoint] = []
        
        // Simple edge detection - find pixels that are page (1.0) but have at least one background neighbor
        for y in 1..<(height-1) {
            for x in 1..<(width-1) {
                if mask[y][x] > 0.5 { // This is a page pixel
                    // Check if it's on the boundary (has at least one background neighbor)
                    let hasBackgroundNeighbor = mask[y-1][x] < 0.5 || mask[y+1][x] < 0.5 ||
                                              mask[y][x-1] < 0.5 || mask[y][x+1] < 0.5
                    
                    if hasBackgroundNeighbor {
                        contourPoints.append(CGPoint(x: x, y: y))
                    }
                }
            }
        }
        
        print("🎭🎭🎭 SegmentationDetector: Found \(contourPoints.count) contour points")
        return contourPoints
    }
    
    /// Calculate bounding box from mask
    private static func calculateBoundingBox(from mask: [[Float]]) -> CGRect {
        let height = mask.count
        let width = mask[0].count
        
        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0
        
        for y in 0..<height {
            for x in 0..<width {
                if mask[y][x] > 0.5 {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }
        
        guard minX < width && minY < height else {
            return CGRect.zero
        }
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    /// Calculate confidence score from probabilities
    private static func calculateConfidence(from probabilities: MLMultiArray, mask: [[Float]]) -> Float {
        let shape = probabilities.shape.map { Int(truncating: $0) }
        let height = shape[2]
        let width = shape[3]
        
        var totalConf: Float = 0.0
        var pagePixelCount = 0
        
        for h in 0..<height {
            for w in 0..<width {
                if mask[h][w] > 0.5 {
                    let pageProb = probabilities[[0, 1, h, w] as [NSNumber]].floatValue
                    totalConf += pageProb
                    pagePixelCount += 1
                }
            }
        }
        
        return pagePixelCount > 0 ? totalConf / Float(pagePixelCount) : 0.0
    }
    
    /// Map points from 320x320 space back to original image coordinates
    private static func mapToOriginalCoordinates(_ points: [CGPoint], from sourceSize: CGSize, to targetSize: CGSize) -> [CGPoint] {
        let scaleX = targetSize.width / sourceSize.width
        let scaleY = targetSize.height / sourceSize.height
        
        return points.map { point in
            CGPoint(x: point.x * scaleX, y: point.y * scaleY)
        }
    }
    
    /// Map bounding box from 320x320 space back to original image coordinates
    private static func mapBoundingBoxToOriginalCoordinates(_ rect: CGRect, from sourceSize: CGSize, to targetSize: CGSize) -> CGRect {
        let scaleX = targetSize.width / sourceSize.width
        let scaleY = targetSize.height / sourceSize.height
        
        return CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
    }
    
    /// Main function to detect page segmentation using CoreML model
    private static func detectPageSegmentation(
        for request: VNImageRequestHandler,
        originalSize: CGSize,
        completion: @escaping ((PageSegmentationResult?) -> Void)
    ) {
        guard let visionModel = getConfiguredModel() else {
            completion(nil)
            return
        }
        
        // Create CoreML request
        let coreMLRequest = VNCoreMLRequest(model: visionModel) { request, error in
            if let error = error {
                print("🎭🎭🎭 SegmentationDetector: CoreML request failed: \(error)")
                completion(nil)
                return
            }
            
            guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                  let firstResult = results.first,
                  let logits = firstResult.featureValue.multiArrayValue else {
                print("🎭🎭🎭 SegmentationDetector: No valid results from CoreML model")
                completion(nil)
                return
            }
            
            print("🎭🎭🎭 SegmentationDetector: Received logits with shape: \(logits.shape)")
            
            // Apply softmax to get probabilities
            guard let probabilities = applySoftmax(to: logits) else {
                print("🎭🎭🎭 SegmentationDetector: Failed to apply softmax")
                completion(nil)
                return
            }
            
            // Create binary mask
            let mask = createBinaryMask(from: probabilities, threshold: config.threshold)
            
            // Find contour points in 320x320 space
            let contourPoints320 = findContourPoints(from: mask)
            
            // Calculate bounding box in 320x320 space
            let boundingBox320 = calculateBoundingBox(from: mask)
            
            // Calculate confidence
            let confidence = calculateConfidence(from: probabilities, mask: mask)
            
            print("🎭🎭🎭 SegmentationDetector: Confidence: \(String(format: "%.3f", confidence))")
            print("🎭🎭🎭 SegmentationDetector: Bounding box (320x320): \(boundingBox320)")
            
            // Map results back to original image coordinates
            let modelSize = CGSize(width: 320, height: 320)
            let originalContourPoints = mapToOriginalCoordinates(contourPoints320, from: modelSize, to: originalSize)
            let originalBoundingBox = mapBoundingBoxToOriginalCoordinates(boundingBox320, from: modelSize, to: originalSize)
            
            let result = PageSegmentationResult(
                mask: mask,
                boundingBox: originalBoundingBox,
                confidence: confidence,
                contourPoints: originalContourPoints
            )
            
            print("🎭🎭🎭 SegmentationDetector: Successfully detected page segmentation")
            print("🎭🎭🎭 SegmentationDetector: Original bounding box: \(originalBoundingBox)")
            print("🎭🎭🎭 SegmentationDetector: Contour points: \(originalContourPoints.count)")
            
            completion(result)
        }
        
        // Use scaleFit to maintain aspect ratio (letterboxing)
        coreMLRequest.imageCropAndScaleOption = .scaleFit
        
        // Perform the request
        do {
            try request.perform([coreMLRequest])
        } catch {
            print("🎭🎭🎭 SegmentationDetector: Failed to perform request: \(error)")
            completion(nil)
        }
    }
    
    /// Detects page segmentation from the given CVPixelBuffer using CoreML
    ///
    /// - Parameters:
    ///   - pixelBuffer: The pixelBuffer to segment
    ///   - completion: The segmentation result
    static func segmentPage(forPixelBuffer pixelBuffer: CVPixelBuffer, completion: @escaping ((PageSegmentationResult?) -> Void)) {
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        let originalSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        detectPageSegmentation(for: imageRequestHandler, originalSize: originalSize, completion: completion)
    }
    
    /// Detects page segmentation from the given image using CoreML
    ///
    /// - Parameters:
    ///   - image: The image to segment
    ///   - completion: The segmentation result
    static func segmentPage(forImage image: CIImage, completion: @escaping ((PageSegmentationResult?) -> Void)) {
        let imageRequestHandler = VNImageRequestHandler(ciImage: image, options: [:])
        detectPageSegmentation(for: imageRequestHandler, originalSize: image.extent.size, completion: completion)
    }
    
    /// Detects page segmentation from the given image with orientation using CoreML
    ///
    /// - Parameters:
    ///   - image: The image to segment
    ///   - orientation: The orientation of the image
    ///   - completion: The segmentation result
    static func segmentPage(
        forImage image: CIImage,
        orientation: CGImagePropertyOrientation,
        completion: @escaping ((PageSegmentationResult?) -> Void)
    ) {
        let imageRequestHandler = VNImageRequestHandler(ciImage: image, orientation: orientation, options: [:])
        let orientedImage = image.oriented(orientation)
        detectPageSegmentation(for: imageRequestHandler, originalSize: orientedImage.extent.size, completion: completion)
    }
    
    // MARK: - Quadrilateral Conversion
    
    /// Convert segmentation result to quadrilateral by finding the best-fit rectangle
    /// - Parameter segmentationResult: The page segmentation result
    /// - Returns: A quadrilateral representing the detected page bounds, or nil if conversion fails
    static func convertToQuadrilateral(from segmentationResult: PageSegmentationResult) -> Quadrilateral? {
        let contourPoints = segmentationResult.contourPoints
        
        guard contourPoints.count >= 4 else {
            print("🎭🎭🎭 SegmentationDetector: Not enough contour points (\(contourPoints.count)) to form quadrilateral")
            return nil
        }
        
        print("🎭🎭🎭 SegmentationDetector: Converting \(contourPoints.count) contour points to quadrilateral")
        
        // Find the four corner points by finding extreme points
        let corners = findCornerPoints(from: contourPoints)
        
        guard corners.count == 4 else {
            print("🎭🎭🎭 SegmentationDetector: Failed to find 4 corner points")
            return nil
        }
        
        let quadrilateral = Quadrilateral(
            topLeft: corners[0],
            topRight: corners[1],
            bottomRight: corners[2],
            bottomLeft: corners[3]
        )
        
        print("🎭🎭🎭 SegmentationDetector: Successfully converted to quadrilateral:")
        print("🎭🎭🎭 SegmentationDetector:   Top-Left: \(quadrilateral.topLeft)")
        print("🎭🎭🎭 SegmentationDetector:   Top-Right: \(quadrilateral.topRight)")
        print("🎭🎭🎭 SegmentationDetector:   Bottom-Right: \(quadrilateral.bottomRight)")
        print("🎭🎭🎭 SegmentationDetector:   Bottom-Left: \(quadrilateral.bottomLeft)")
        
        return quadrilateral
    }
    
    /// Find four corner points from contour points
    private static func findCornerPoints(from contourPoints: [CGPoint]) -> [CGPoint] {
        guard !contourPoints.isEmpty else { return [] }
        
        // Find extreme points
        let leftMost = contourPoints.min { $0.x < $1.x }!
        let rightMost = contourPoints.max { $0.x < $1.x }!
        let topMost = contourPoints.min { $0.y < $1.y }!
        let bottomMost = contourPoints.max { $0.y < $1.y }!
        
        // Find corner points by looking for points closest to the corners of the bounding box
        let bounds = segmentationBounds(of: contourPoints)
        
        let topLeft = findClosestPoint(to: CGPoint(x: bounds.minX, y: bounds.minY), in: contourPoints)
        let topRight = findClosestPoint(to: CGPoint(x: bounds.maxX, y: bounds.minY), in: contourPoints)
        let bottomRight = findClosestPoint(to: CGPoint(x: bounds.maxX, y: bounds.maxY), in: contourPoints)
        let bottomLeft = findClosestPoint(to: CGPoint(x: bounds.minX, y: bounds.maxY), in: contourPoints)
        
        return [topLeft, topRight, bottomRight, bottomLeft]
    }
    
    /// Find the point in the array closest to the target point
    private static func findClosestPoint(to target: CGPoint, in points: [CGPoint]) -> CGPoint {
        return points.min { point1, point2 in
            let dist1 = distance(from: point1, to: target)
            let dist2 = distance(from: point2, to: target)
            return dist1 < dist2
        } ?? target
    }
    
    /// Calculate distance between two points
    private static func distance(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
        let dx = point1.x - point2.x
        let dy = point1.y - point2.y
        return sqrt(dx * dx + dy * dy)
    }
    
    /// Get bounds of a set of points
    private static func segmentationBounds(of points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .zero }
        
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        
        let minX = xs.min()!
        let maxX = xs.max()!
        let minY = ys.min()!
        let maxY = ys.max()!
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    // MARK: - Convenience Methods for Quadrilateral Detection
    
    /// Detects rectangles from the given CVPixelBuffer using segmentation and converts to Quadrilateral
    ///
    /// - Parameters:
    ///   - pixelBuffer: The pixelBuffer to detect rectangles on.
    ///   - completion: The detected rectangle on the CVPixelBuffer
    static func rectangle(forPixelBuffer pixelBuffer: CVPixelBuffer, completion: @escaping ((Quadrilateral?) -> Void)) {
        segmentPage(forPixelBuffer: pixelBuffer) { segmentationResult in
            guard let result = segmentationResult else {
                completion(nil)
                return
            }
            
            let quadrilateral = convertToQuadrilateral(from: result)
            completion(quadrilateral)
        }
    }
    
    /// Detects rectangles from the given image using segmentation and converts to Quadrilateral
    ///
    /// - Parameters:
    ///   - image: The image to detect rectangles on.
    ///   - completion: The detected rectangle on the image.
    static func rectangle(forImage image: CIImage, completion: @escaping ((Quadrilateral?) -> Void)) {
        segmentPage(forImage: image) { segmentationResult in
            guard let result = segmentationResult else {
                completion(nil)
                return
            }
            
            let quadrilateral = convertToQuadrilateral(from: result)
            completion(quadrilateral)
        }
    }
}
