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
public enum CoreMLSegmentationDetector {
    
    private static var visionModel: VNCoreMLModel?
    private static var config: CoreMLSegmentationConfig = .default
    
    /// Configure the CoreML segmentation model
    /// - Parameters:
    ///   - model: The CoreML DeepLabV3 model to use for page segmentation
    ///   - config: Segmentation configuration including thresholds
    public static func configure(with model: MLModel, config: CoreMLSegmentationConfig = .default) throws {
        let visionMLModel = try VNCoreMLModel(for: model)
        self.visionModel = visionMLModel
        self.config = config
        print("🎭🎭🎭 SegmentationDetector: Successfully configured with provided CoreML model")
        print("🎭🎭🎭 SegmentationDetector: Threshold: \(config.threshold)")
        print("🎭🎭🎭 SegmentationDetector: Min contour area: \(config.minContourArea)")
        print("🎭🎭🎭 SegmentationDetector: Apply morphology: \(config.applyMorphology)")
    }
    
    /// Letterbox parameters for image preprocessing (matching .scaleFit)
    private struct LetterboxParameters {
        let scale: CGFloat
        let padX: CGFloat
        let padY: CGFloat
    }

    /// Calculate letterbox parameters for 320x320 input while preserving aspect ratio
    private static func letterboxParameters(originalSize: CGSize, targetSize: CGFloat = 320) -> LetterboxParameters {
        let scale = min(targetSize / originalSize.width, targetSize / originalSize.height)
        let scaledWidth = round(originalSize.width * scale)
        let scaledHeight = round(originalSize.height * scale)
        let padX = (targetSize - scaledWidth) / 2.0
        let padY = (targetSize - scaledHeight) / 2.0

        print("🎭🎭🎭 SegmentationDetector: Letterbox parameters:")
        print("🎭🎭🎭 SegmentationDetector:   Original size: \(originalSize)")
        print("🎭🎭🎭 SegmentationDetector:   Target size: \(targetSize)")
        print("🎭🎭🎭 SegmentationDetector:   Scale: \(scale)")
        print("🎭🎭🎭 SegmentationDetector:   Scaled size: (\(scaledWidth), \(scaledHeight))")
        print("🎭🎭🎭 SegmentationDetector:   Padding: (\(padX), \(padY))")

        return LetterboxParameters(scale: scale, padX: padX, padY: padY)
    }

    /// Convenience method to configure with a model from bundle
    /// - Parameters:
    ///   - modelName: Name of the model file (without extension)
    ///   - bundle: Bundle containing the model (defaults to main bundle)
    ///   - config: Segmentation configuration including thresholds
    public static func configure(modelName: String, in bundle: Bundle = Bundle.main, config: CoreMLSegmentationConfig = .default) throws {
        guard let modelURL = bundle.url(forResource: modelName, withExtension: "mlpackage") else {
            throw NSError(domain: "CoreMLSegmentationDetector", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "CoreML segmentation model '\(modelName).mlpackage' not found in bundle"
            ])
        }
        
        let model = try MLModel(contentsOf: modelURL)
        try configure(with: model, config: config)
    }
    
    /// Check if a CoreML segmentation model has been configured
    public static var isConfigured: Bool {
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
        var minPageProb: Float = 1.0
        var maxPageProb: Float = 0.0
        var sumPageProb: Float = 0.0
        
        for h in 0..<height {
            for w in 0..<width {
                let pageProb = probabilities[[0, 1, h, w] as [NSNumber]].floatValue
                totalPixels += 1
                sumPageProb += pageProb
                minPageProb = min(minPageProb, pageProb)
                maxPageProb = max(maxPageProb, pageProb)
                
                if pageProb > threshold {
                    mask[h][w] = 1.0
                    pagePixelCount += 1
                }
            }
        }
        
        let pageRatio = Float(pagePixelCount) / Float(totalPixels)
        let avgPageProb = sumPageProb / Float(totalPixels)
        print("🎭🎭🎭 SegmentationDetector: Page pixels: \(pagePixelCount)/\(totalPixels) (\(String(format: "%.1f", pageRatio * 100))%)")
        print("🎭🎭🎭 SegmentationDetector: Page prob range: [\(String(format: "%.3f", minPageProb)), \(String(format: "%.3f", maxPageProb))], avg: \(String(format: "%.3f", avgPageProb))")
        
        return mask
    }

    /// Perform morphological closing (dilation followed by erosion) on a binary mask
    /// - Parameters:
    ///   - mask: 2D binary mask (values 0.0 or 1.0)
    ///   - iterations: Number of times to apply the close operation
    /// - Returns: Cleaned binary mask
    private static func morphologicalClose(_ mask: [[Float]], iterations: Int) -> [[Float]] {
        guard iterations > 0 else { return mask }
        var current = mask
        for _ in 0..<iterations {
            current = dilate(current)
            current = erode(current)
        }
        return current
    }

    /// Dilate binary mask with 3x3 cross-shaped structuring element
    private static func dilate(_ mask: [[Float]]) -> [[Float]] {
        let height = mask.count
        let width = mask.first?.count ?? 0
        guard height > 0 && width > 0 else { return mask }
        var out = mask
        for y in 0..<height {
            for x in 0..<width {
                var maxVal: Float = 0.0
                for dy in -1...1 {
                    for dx in -1...1 {
                        if abs(dx) + abs(dy) > 1 { continue } // cross kernel
                        let ny = y + dy
                        let nx = x + dx
                        if ny >= 0 && ny < height && nx >= 0 && nx < width {
                            maxVal = max(maxVal, mask[ny][nx])
                        }
                    }
                }
                out[y][x] = maxVal
            }
        }
        return out
    }

    /// Erode binary mask with 3x3 cross-shaped structuring element
    private static func erode(_ mask: [[Float]]) -> [[Float]] {
        let height = mask.count
        let width = mask.first?.count ?? 0
        guard height > 0 && width > 0 else { return mask }
        var out = mask
        for y in 0..<height {
            for x in 0..<width {
                var minVal: Float = 1.0
                for dy in -1...1 {
                    for dx in -1...1 {
                        if abs(dx) + abs(dy) > 1 { continue } // cross kernel
                        let ny = y + dy
                        let nx = x + dx
                        if ny >= 0 && ny < height && nx >= 0 && nx < width {
                            minVal = min(minVal, mask[ny][nx])
                        } else {
                            minVal = 0.0
                        }
                    }
                }
                out[y][x] = minVal
            }
        }
        return out
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

    /// Render a binary mask (page=1.0) to a UIImage at the original image size using the same letterbox transform inversion
    public static func renderMaskImage(originalSize: CGSize, mask: [[Float]], threshold: Float = 0.5, color: UIColor = .systemBlue, alpha: CGFloat = 0.45) -> UIImage? {
        let width = Int(originalSize.width)
        let height = Int(originalSize.height)
        guard width > 0, height > 0, let firstRow = mask.first, firstRow.count > 0 else { return nil }

        // RGBA buffer
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        // Precompute color components (premultiplied alpha)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let outA = UInt8((alpha * 255).rounded())
        let outR = UInt8((r * 255).rounded())
        let outG = UInt8((g * 255).rounded())
        let outB = UInt8((b * 255).rounded())

        // Inverse letterbox for mapping 320x320 mask -> original
        let lb = letterboxParameters(originalSize: originalSize)
        let h = mask.count
        let w = mask[0].count
        
        // Calculate pixel size in original image space (how many original pixels per mask pixel)
        let pixelScale = 1.0 / lb.scale
        let pixelWidth = Int(ceil(pixelScale))
        let pixelHeight = Int(ceil(pixelScale))
        
        for y in 0..<h {
            for x in 0..<w {
                if mask[y][x] >= threshold {
                    // Calculate the center of this mask pixel in original image coordinates
                    let centerX = (CGFloat(x) - lb.padX) / lb.scale
                    let centerY = (CGFloat(y) - lb.padY) / lb.scale
                    
                    // Fill a rectangle around this center point
                    let startX = Int(centerX) - pixelWidth / 2
                    let startY = Int(centerY) - pixelHeight / 2
                    let endX = startX + pixelWidth
                    let endY = startY + pixelHeight
                    
                    for py in max(0, startY)..<min(height, endY) {
                        for px in max(0, startX)..<min(width, endX) {
                            let idx = (py * width + px) * 4
                            pixels[idx + 0] = outR
                            pixels[idx + 1] = outG
                            pixels[idx + 2] = outB
                            pixels[idx + 3] = outA
                        }
                    }
                }
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let result: UIImage? = pixels.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return nil }
            guard let ctx = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            guard let cgImage = ctx.makeImage() else { return nil }
            return UIImage(cgImage: cgImage)
        }
        
        // Debug: Count non-transparent pixels
        var opaquePixelCount = 0
        for i in stride(from: 3, to: pixels.count, by: 4) {
            if pixels[i] > 0 { opaquePixelCount += 1 }
        }
        print("🎭🎭🎭 SegmentationDetector: Rendered overlay image: \(width)x\(height), opaque pixels: \(opaquePixelCount)/\(width*height)")
        
        return result
    }
    
    /// Unletterbox points from 320x320 space back to original image coordinates
    private static func unletterboxPoints(_ points320: [CGPoint], letterbox: LetterboxParameters) -> [CGPoint] {
        return points320.map { point in
            let originalX = (point.x - letterbox.padX) / letterbox.scale
            let originalY = (point.y - letterbox.padY) / letterbox.scale
            return CGPoint(x: originalX, y: originalY)
        }
    }

    /// Unletterbox rect from 320x320 space back to original image coordinates
    private static func unletterboxRect(_ rect320: CGRect, letterbox: LetterboxParameters) -> CGRect {
        // Convert rect to four points, unletterbox, then rebuild rect from extremes
        let p1 = CGPoint(x: rect320.minX, y: rect320.minY)
        let p2 = CGPoint(x: rect320.maxX, y: rect320.minY)
        let p3 = CGPoint(x: rect320.maxX, y: rect320.maxY)
        let p4 = CGPoint(x: rect320.minX, y: rect320.maxY)
        let mapped = unletterboxPoints([p1, p2, p3, p4], letterbox: letterbox)
        let xs = mapped.map { $0.x }
        let ys = mapped.map { $0.y }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return .zero
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
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
            var mask = createBinaryMask(from: probabilities, threshold: config.threshold)

            // Optional morphology to clean mask (dilate then erode)
            if config.applyMorphology {
                mask = morphologicalClose(mask, iterations: 1)
            }
            
            // Find contour points in 320x320 space
            let contourPoints320 = findContourPoints(from: mask)
            
            // Calculate bounding box in 320x320 space
            let boundingBox320 = calculateBoundingBox(from: mask)
            
            // Calculate confidence
            let confidence = calculateConfidence(from: probabilities, mask: mask)
            
            print("🎭🎭🎭 SegmentationDetector: Confidence: \(String(format: "%.3f", confidence))")
            print("🎭🎭🎭 SegmentationDetector: Bounding box (320x320): \(boundingBox320)")
            
            // Map results back to original image coordinates (undo letterboxing)
            let letterbox = letterboxParameters(originalSize: originalSize)
            let originalContourPoints = unletterboxPoints(contourPoints320, letterbox: letterbox)
            let originalBoundingBox = unletterboxRect(boundingBox320, letterbox: letterbox)
            
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
        coreMLRequest.imageCropAndScaleOption = VNImageCropAndScaleOption.scaleFit
        
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
    public static func segmentPage(forPixelBuffer pixelBuffer: CVPixelBuffer, completion: @escaping ((PageSegmentationResult?) -> Void)) {
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        let originalSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        detectPageSegmentation(for: imageRequestHandler, originalSize: originalSize, completion: completion)
    }
    
    /// Detects page segmentation from the given image using CoreML
    ///
    /// - Parameters:
    ///   - image: The image to segment
    ///   - completion: The segmentation result
    public static func segmentPage(forImage image: CIImage, completion: @escaping ((PageSegmentationResult?) -> Void)) {
        let imageRequestHandler = VNImageRequestHandler(ciImage: image, options: [:])
        detectPageSegmentation(for: imageRequestHandler, originalSize: image.extent.size, completion: completion)
    }
    
    /// Detects page segmentation from the given image with orientation using CoreML
    ///
    /// - Parameters:
    ///   - image: The image to segment
    ///   - orientation: The orientation of the image
    ///   - completion: The segmentation result
    public static func segmentPage(
        forImage image: CIImage,
        orientation: CGImagePropertyOrientation,
        completion: @escaping ((PageSegmentationResult?) -> Void)
    ) {
        let imageRequestHandler = VNImageRequestHandler(ciImage: image, orientation: orientation, options: [:])
        let orientedImage = image.oriented(orientation)
        detectPageSegmentation(for: imageRequestHandler, originalSize: orientedImage.extent.size, completion: completion)
    }

    // MARK: - Still Image Convenience

    /// Segments a UIImage and optionally returns a rendered mask image at original resolution
    /// - Parameters:
    ///   - image: Source image
    ///   - threshold: Probability threshold for page class
    ///   - completion: Called with segmentation result and optional mask UIImage
    public static func segmentUIImage(_ image: UIImage, threshold: Float = 0.5, completion: @escaping (PageSegmentationResult?, UIImage?) -> Void) {
        guard let ciImage = CIImage(image: image) else {
            completion(nil, nil)
            return
        }
        segmentPage(forImage: ciImage) { result in
            guard let result else {
                completion(nil, nil)
                return
            }
            // Render mask image showing individual page pixels
            let maskImage = renderMaskImage(originalSize: image.size, mask: result.mask, threshold: threshold, color: .systemBlue, alpha: 0.45)
            completion(result, maskImage)
        }
    }
    
    // MARK: - Quadrilateral Conversion
    
    /// Convert segmentation result to quadrilateral by finding the best-fit rectangle
    /// - Parameter segmentationResult: The page segmentation result
    /// - Returns: A quadrilateral representing the detected page bounds, or nil if conversion fails
    public static func convertToQuadrilateral(from segmentationResult: PageSegmentationResult) -> Quadrilateral? {
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
    public static func rectangle(forPixelBuffer pixelBuffer: CVPixelBuffer, completion: @escaping ((Quadrilateral?) -> Void)) {
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
    public static func rectangle(forImage image: CIImage, completion: @escaping ((Quadrilateral?) -> Void)) {
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
