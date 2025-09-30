//
//  CaptureManager.swift
//  WeScan
//
//  Created by Boris Emorine on 2/8/18.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import AVFoundation
import CoreMotion
import Foundation
import UIKit
import Vision
import CoreImage

/// A set of functions that inform the delegate object of the state of the detection.
protocol RectangleDetectionDelegateProtocol: NSObjectProtocol {

    /// Called when the capture of a picture has started.
    ///
    /// - Parameters:
    ///   - captureSessionManager: The `CaptureSessionManager` instance that started capturing a picture.
    func didStartCapturingPicture(for captureSessionManager: CaptureSessionManager)

    /// Called when a quadrilateral has been detected.
    /// - Parameters:
    ///   - captureSessionManager: The `CaptureSessionManager` instance that has detected a quadrilateral.
    ///   - quad: The detected quadrilateral in the coordinates of the image.
    ///   - imageSize: The size of the image the quadrilateral has been detected on.
    func captureSessionManager(_ captureSessionManager: CaptureSessionManager, didDetectQuad quad: Quadrilateral?, _ imageSize: CGSize)

    /// Called when a picture with or without a quadrilateral has been captured.
    ///
    /// - Parameters:
    ///   - captureSessionManager: The `CaptureSessionManager` instance that has captured a picture.
    ///   - picture: The picture that has been captured.
    ///   - quad: The quadrilateral that was detected in the picture's coordinates if any.
    func captureSessionManager(
        _ captureSessionManager: CaptureSessionManager,
        didCapturePicture picture: UIImage,
        withQuad quad: Quadrilateral?
    )

    /// Called when an error occurred with the capture session manager.
    /// - Parameters:
    ///   - captureSessionManager: The `CaptureSessionManager` that encountered an error.
    ///   - error: The encountered error.
    func captureSessionManager(_ captureSessionManager: CaptureSessionManager, didFailWithError error: Error)
}

/// The CaptureSessionManager is responsible for setting up and managing the AVCaptureSession and the functions related to capturing.
final class CaptureSessionManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    private let videoPreviewLayer: AVCaptureVideoPreviewLayer
    private let captureSession = AVCaptureSession()
    private let rectangleFunnel = RectangleFeaturesFunnel()
    weak var delegate: RectangleDetectionDelegateProtocol?
    private var displayedRectangleResult: RectangleDetectorResult?
    
    /// Enable text-based rectangle detection (requires iOS 11+)
    var useTextBasedDetection: Bool = true
    private var photoOutput = AVCapturePhotoOutput()

    /// Whether the CaptureSessionManager should be detecting quadrilaterals.
    private var isDetecting = true

    /// The number of times no rectangles have been found in a row.
    private var noRectangleCount = 0

    /// The minimum number of time required by `noRectangleCount` to validate that no rectangles have been found.
    private let noRectangleThreshold = 8

    // MARK: Life Cycle

    init?(videoPreviewLayer: AVCaptureVideoPreviewLayer, delegate: RectangleDetectionDelegateProtocol? = nil) {
        self.videoPreviewLayer = videoPreviewLayer

        if delegate != nil {
            self.delegate = delegate
        }

        super.init()

        guard let device = AVCaptureDevice.default(for: AVMediaType.video) else {
            let error = ImageScannerControllerError.inputDevice
            delegate?.captureSessionManager(self, didFailWithError: error)
            return nil
        }

        captureSession.beginConfiguration()

        photoOutput.isHighResolutionCaptureEnabled = true

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true

        defer {
            device.unlockForConfiguration()
            captureSession.commitConfiguration()
        }

        guard let deviceInput = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(deviceInput),
            captureSession.canAddOutput(photoOutput),
            captureSession.canAddOutput(videoOutput) else {
                let error = ImageScannerControllerError.inputDevice
                delegate?.captureSessionManager(self, didFailWithError: error)
                return
        }

        do {
            try device.lockForConfiguration()
        } catch {
            let error = ImageScannerControllerError.inputDevice
            delegate?.captureSessionManager(self, didFailWithError: error)
            return
        }

        device.isSubjectAreaChangeMonitoringEnabled = true

        captureSession.addInput(deviceInput)
        captureSession.addOutput(photoOutput)
        captureSession.addOutput(videoOutput)

        let photoPreset = AVCaptureSession.Preset.photo

        if captureSession.canSetSessionPreset(photoPreset) {
            captureSession.sessionPreset = photoPreset

            if photoOutput.isLivePhotoCaptureSupported {
                photoOutput.isLivePhotoCaptureEnabled = true
            }
        }

        videoPreviewLayer.session = captureSession
        videoPreviewLayer.videoGravity = .resizeAspectFill

        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video_ouput_queue"))
    }

    // MARK: Capture Session Life Cycle

    /// Starts the camera and detecting quadrilaterals.
    internal func start() {
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch authorizationStatus {
        case .authorized:
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isDetecting = true
                }
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if granted {
                        self.start()
                    } else {
                        let error = ImageScannerControllerError.authorization
                        self.delegate?.captureSessionManager(self, didFailWithError: error)
                    }
                }
            })
        default:
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let error = ImageScannerControllerError.authorization
                self.delegate?.captureSessionManager(self, didFailWithError: error)
            }
        }
    }

    internal func stop() {
        captureSession.stopRunning()
    }

    internal func capturePhoto() {
        // Log the aspect ratio of the rectangle being captured
        if let currentRect = displayedRectangleResult?.rectangle {
            let aspectRatio = currentRect.aspectRatio
            let area = currentRect.area
            print("🔥 MANUAL CAPTURE - IMAGE ASPECT RATIO: \(String(format: "%.3f", aspectRatio)) | AREA: \(String(format: "%.0f", area)) pixels")
            print("🔥 MANUAL CAPTURE - RECTANGLE BOUNDS: TL(\(String(format: "%.1f", currentRect.topLeft.x)), \(String(format: "%.1f", currentRect.topLeft.y))) TR(\(String(format: "%.1f", currentRect.topRight.x)), \(String(format: "%.1f", currentRect.topRight.y))) BR(\(String(format: "%.1f", currentRect.bottomRight.x)), \(String(format: "%.1f", currentRect.bottomRight.y))) BL(\(String(format: "%.1f", currentRect.bottomLeft.x)), \(String(format: "%.1f", currentRect.bottomLeft.y)))")
        } else {
            print("🔥 MANUAL CAPTURE - NO RECTANGLE DETECTED (will capture full frame)")
        }
        
        guard let connection = photoOutput.connection(with: .video), connection.isEnabled, connection.isActive else {
            let error = ImageScannerControllerError.capture
            delegate?.captureSessionManager(self, didFailWithError: error)
            return
        }
        CaptureSession.current.setImageOrientation()
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.isHighResolutionPhotoEnabled = true
        photoSettings.isAutoStillImageStabilizationEnabled = true
        photoOutput.capturePhoto(with: photoSettings, delegate: self)
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isDetecting == true,
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))

        if #available(iOS 15.0, *) {
            // Try CoreML-based segmentation detection first, fall back to Vision if model not available
            CoreMLSegmentationDetector.rectangle(forPixelBuffer: pixelBuffer) { [weak self] rectangle in
                guard let self = self else { return }
                
                // If segmentation detection failed, fall back to traditional Vision detection
                if rectangle == nil {
                    VisionRectangleDetector.rectangle(forPixelBuffer: pixelBuffer) { fallbackRectangle in
                        self.processRectangle(rectangle: fallbackRectangle, imageSize: imageSize)
                    }
                } else {
                    self.processRectangle(rectangle: rectangle, imageSize: imageSize)
                }
            }
        } else if #available(iOS 11.0, *) {
            // Fall back to Vision for older iOS versions
            VisionRectangleDetector.rectangle(forPixelBuffer: pixelBuffer) { [weak self] rectangle in
                guard let self = self else { return }
                self.processRectangle(rectangle: rectangle, imageSize: imageSize)
            }
        } else {
            let finalImage = CIImage(cvPixelBuffer: pixelBuffer)
            CIRectangleDetector.rectangle(forImage: finalImage) { rectangle in
                self.processRectangle(rectangle: rectangle, imageSize: imageSize)
            }
        }
    }

    private func processRectangle(rectangle: Quadrilateral?, imageSize: CGSize) {
        if let rectangle {
            print("📸📸📸 CaptureSession: Rectangle detected! Image size: \(imageSize)")
            self.noRectangleCount = 0
            self.rectangleFunnel
                .add(rectangle, currentlyDisplayedRectangle: self.displayedRectangleResult?.rectangle) { [weak self] result, rectangle in

                guard let self else {
                    return
                }

                let shouldAutoScan = (result == .showAndAutoScan)
                print("📸📸📸 CaptureSession: Funnel result - shouldAutoScan: \(shouldAutoScan)")
                print("📸📸📸 CaptureSession: Auto-scan enabled: \(CaptureSession.current.isAutoScanEnabled), isEditing: \(CaptureSession.current.isEditing)")
                
                self.displayRectangleResult(rectangleResult: RectangleDetectorResult(rectangle: rectangle, imageSize: imageSize))
                if shouldAutoScan, CaptureSession.current.isAutoScanEnabled, !CaptureSession.current.isEditing {
                    print("📸📸📸 CaptureSession: CAPTURING PHOTO! 📷")
                    
                    // Calculate and log the exact aspect ratio of the captured rectangle
                    let capturedAspectRatio = rectangle.aspectRatio
                    let capturedArea = rectangle.area
                    print("🔥 CAPTURED IMAGE ASPECT RATIO: \(String(format: "%.3f", capturedAspectRatio)) | AREA: \(String(format: "%.0f", capturedArea)) pixels")
                    print("🔥 RECTANGLE BOUNDS: TL(\(String(format: "%.1f", rectangle.topLeft.x)), \(String(format: "%.1f", rectangle.topLeft.y))) TR(\(String(format: "%.1f", rectangle.topRight.x)), \(String(format: "%.1f", rectangle.topRight.y))) BR(\(String(format: "%.1f", rectangle.bottomRight.x)), \(String(format: "%.1f", rectangle.bottomRight.y))) BL(\(String(format: "%.1f", rectangle.bottomLeft.x)), \(String(format: "%.1f", rectangle.bottomLeft.y)))")
                    
                    capturePhoto()
                } else if shouldAutoScan {
                    print("📸📸📸 CaptureSession: Auto-scan triggered but conditions not met - autoScan: \(CaptureSession.current.isAutoScanEnabled), editing: \(CaptureSession.current.isEditing)")
                }
            }

        } else {
            print("📸📸📸 CaptureSession: No rectangle detected")
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.noRectangleCount += 1
                print("📸📸📸 CaptureSession: No rectangle count: \(self.noRectangleCount)/\(self.noRectangleThreshold)")

                if self.noRectangleCount > self.noRectangleThreshold {
                    print("📸📸📸 CaptureSession: Clearing displayed rectangle - too many frames without detection")
                    // Reset the currentAutoScanPassCount, so the threshold is restarted the next time a rectangle is found
                    self.rectangleFunnel.currentAutoScanPassCount = 0

                    // Remove the currently displayed rectangle as no rectangles are being found anymore
                    self.displayedRectangleResult = nil
                    self.delegate?.captureSessionManager(self, didDetectQuad: nil, imageSize)
                }
            }
            return

        }
    }

    @discardableResult private func displayRectangleResult(rectangleResult: RectangleDetectorResult) -> Quadrilateral {
        displayedRectangleResult = rectangleResult

        let quad = rectangleResult.rectangle.toCartesian(withHeight: rectangleResult.imageSize.height)

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.delegate?.captureSessionManager(self, didDetectQuad: quad, rectangleResult.imageSize)
        }

        return quad
    }

}

extension CaptureSessionManager: AVCapturePhotoCaptureDelegate {

    // swiftlint:disable function_parameter_count
    func photoOutput(_ captureOutput: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photoSampleBuffer: CMSampleBuffer?,
                     previewPhoto previewPhotoSampleBuffer: CMSampleBuffer?,
                     resolvedSettings: AVCaptureResolvedPhotoSettings,
                     bracketSettings: AVCaptureBracketedStillImageSettings?,
                     error: Error?
    ) {
        if let error {
            delegate?.captureSessionManager(self, didFailWithError: error)
            return
        }

        isDetecting = false
        rectangleFunnel.currentAutoScanPassCount = 0
        delegate?.didStartCapturingPicture(for: self)

        if let sampleBuffer = photoSampleBuffer,
            let imageData = AVCapturePhotoOutput.jpegPhotoDataRepresentation(
                forJPEGSampleBuffer: sampleBuffer,
                previewPhotoSampleBuffer: nil
            ) {
            completeImageCapture(with: imageData)
        } else {
            let error = ImageScannerControllerError.capture
            delegate?.captureSessionManager(self, didFailWithError: error)
            return
        }

    }

    @available(iOS 11.0, *)
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            delegate?.captureSessionManager(self, didFailWithError: error)
            return
        }

        isDetecting = false
        rectangleFunnel.currentAutoScanPassCount = 0
        delegate?.didStartCapturingPicture(for: self)

        if let imageData = photo.fileDataRepresentation() {
            completeImageCapture(with: imageData)
        } else {
            let error = ImageScannerControllerError.capture
            delegate?.captureSessionManager(self, didFailWithError: error)
            return
        }
    }

    /// Completes the image capture by processing the image, and passing it to the delegate object.
    /// This function is necessary because the capture functions for iOS 10 and 11 are decoupled.
    private func completeImageCapture(with imageData: Data) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            CaptureSession.current.isEditing = true
            guard let image = UIImage(data: imageData) else {
                let error = ImageScannerControllerError.capture
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }
                    self.delegate?.captureSessionManager(self, didFailWithError: error)
                }
                return
            }

            var angle: CGFloat = 0.0

            switch image.imageOrientation {
            case .right:
                angle = CGFloat.pi / 2
            case .up:
                angle = CGFloat.pi
            default:
                break
            }

            var quad: Quadrilateral?
            if let displayedRectangleResult = self?.displayedRectangleResult {
                quad = self?.displayRectangleResult(rectangleResult: displayedRectangleResult)
                quad = quad?.scale(displayedRectangleResult.imageSize, image.size, withRotationAngle: angle)
            }

            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.delegate?.captureSessionManager(self, didCapturePicture: image, withQuad: quad)
            }
        }
    }
}

/// Data structure representing the result of the detection of a quadrilateral.
private struct RectangleDetectorResult {

    /// The detected quadrilateral.
    let rectangle: Quadrilateral

    /// The size of the image the quadrilateral was detected on.
    let imageSize: CGSize

}
