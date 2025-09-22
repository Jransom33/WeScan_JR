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
    
    private static var coreMLModel: MLModel?
    private static var visionModel: VNCoreMLModel?
    
    /// Load the CoreML model for corner detection
    private static func loadModel() -> VNCoreMLModel? {
        if let existingModel = visionModel {
            return existingModel
        }
        
        // Try to find the model in different locations
        var modelURL: URL?
        
        // Strategy 1: Look in the consuming app's main bundle FIRST
        // This allows users to include their own trained model in their app
        print("📸📸📸 CoreMLDetector: Searching for model in main app bundle...")
        modelURL = Bundle.main.url(forResource: "CornerKeypoints_model_epoch_30_simple", withExtension: "mlpackage")
        if modelURL != nil {
            print("📸📸📸 CoreMLDetector: Found model in main app bundle")
        }
        
        // Strategy 2: Try alternative model names that users might prefer
        if modelURL == nil {
            let alternativeNames = [
                "CornerKeypoints",
                "DocumentCornerDetector", 
                "PageCornerModel",
                "BookCornerDetector"
            ]
            
            for name in alternativeNames {
                modelURL = Bundle.main.url(forResource: name, withExtension: "mlpackage")
                if modelURL != nil {
                    print("📸📸📸 CoreMLDetector: Found model with alternative name: \(name)")
                    break
                }
            }
        }
        
        // Strategy 3: Fall back to framework bundle (for default/demo purposes)
        if modelURL == nil {
            print("📸📸📸 CoreMLDetector: Model not found in main bundle, checking framework bundle...")
            let frameworkBundle = Bundle(for: ScannerViewController.self)
            modelURL = frameworkBundle.url(forResource: "CornerKeypoints_model_epoch_30_simple", withExtension: "mlpackage")
            if modelURL != nil {
                print("📸📸📸 CoreMLDetector: Found model in framework bundle")
            }
        }
        
        // Strategy 4: Development fallback - check current directory
        if modelURL == nil {
            print("📸📸📸 CoreMLDetector: Checking development directory...")
            let currentDir = FileManager.default.currentDirectoryPath
            let devPath = "\(currentDir)/CornerKeypoints_model_epoch_30_simple.mlpackage"
            if FileManager.default.fileExists(atPath: devPath) {
                modelURL = URL(fileURLWithPath: devPath)
                print("📸📸📸 CoreMLDetector: Found model in development directory")
            }
        }
        
        guard let finalModelURL = modelURL else {
            print("📸📸📸 CoreMLDetector: ❌ Could not find CoreML model in any location!")
            print("📸📸📸 CoreMLDetector: 💡 To use custom corner detection:")
            print("📸📸📸 CoreMLDetector:    1. Add your trained model to your app's bundle")
            print("📸📸📸 CoreMLDetector:    2. Name it 'CornerKeypoints_model_epoch_30_simple.mlpackage'")
            print("📸📸📸 CoreMLDetector:    3. Or use alternative names: CornerKeypoints, DocumentCornerDetector, etc.")
            print("📸📸📸 CoreMLDetector: 🔄 Falling back to traditional rectangle detection...")
            return nil
        }
        
        do {
            let mlModel = try MLModel(contentsOf: finalModelURL)
            let visionMLModel = try VNCoreMLModel(for: mlModel)
            
            self.coreMLModel = mlModel
            self.visionModel = visionMLModel
            
            print("📸📸📸 CoreMLDetector: Successfully loaded CoreML model")
            return visionMLModel
        } catch {
            print("📸📸📸 CoreMLDetector: Failed to load model: \(error)")
            return nil
        }
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
        guard let visionModel = loadModel() else {
            print("📸📸📸 CoreMLDetector: Failed to load model")
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
