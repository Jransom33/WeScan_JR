//
//  ScannerViewController.swift
//  WeScan
//
//  Created by Boris Emorine on 2/8/18.
//  Copyright © 2018 WeTransfer. All rights reserved.
//
//  swiftlint:disable line_length

import AVFoundation
import UIKit

/// The `ScannerViewController` offers an interface to give feedback to the user regarding quadrilaterals that are detected. It also gives the user the opportunity to capture an image with a detected rectangle.
public final class ScannerViewController: UIViewController {

    private var captureSessionManager: CaptureSessionManager?
    private let videoPreviewLayer = AVCaptureVideoPreviewLayer()

    /// The view that shows the focus rectangle (when the user taps to focus, similar to the Camera app)
    private var focusRectangle: FocusRectangleView!

    /// The view that draws the detected rectangles.
    private let quadView = QuadrilateralView()

    /// Whether flash is enabled
    private var flashEnabled = false

    /// The original bar style that was set by the host app
    private var originalBarStyle: UIBarStyle?

    private lazy var shutterButton: ShutterButton = {
        let button = ShutterButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(captureImage(_:)), for: .touchUpInside)
        return button
    }()

    private lazy var cancelButton: UIButton = {
        let button = UIButton()
        button.setTitle(NSLocalizedString("wescan.scanning.cancel", tableName: nil, bundle: Bundle(for: ScannerViewController.self), value: "Cancel", comment: "The cancel button"), for: .normal)
        button.setTitleColor(.black, for: .normal) // Black text for visibility
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(cancelImageScannerController), for: .touchUpInside)
        return button
    }()
    
    // MARK: - New UI Elements (matching user screenshots)
    
    private lazy var galleryButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        let image = UIImage(systemName: "photo.on.rectangle", withConfiguration: config)
        button.setImage(image, for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 30
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(galleryButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var thumbnailButton: UIButton = {
        let button = UIButton(type: .custom)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 30
        button.layer.borderWidth = 2
        button.layer.borderColor = UIColor.white.cgColor
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(thumbnailButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var thumbnailBadge: UILabel = {
        let label = UILabel()
        label.backgroundColor = UIColor(red: 255/255, green: 74/255, blue: 28/255, alpha: 1.0) // #FF4A1C
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textAlignment = .center
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    private lazy var autoScanButton: UIBarButtonItem = {
        let title = NSLocalizedString("wescan.scanning.auto", tableName: nil, bundle: Bundle(for: ScannerViewController.self), value: "Auto", comment: "The auto button state")
        let button = UIBarButtonItem(title: title, style: .plain, target: self, action: #selector(toggleAutoScan))
        button.tintColor = .black  // Black for visibility on light background

        return button
    }()

    private lazy var flashButton: UIBarButtonItem = {
        let image = UIImage(systemName: "bolt.fill", named: "flash", in: Bundle(for: ScannerViewController.self), compatibleWith: nil)
        let button = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(toggleFlash))
        button.tintColor = .black  // Black for visibility on light background

        return button
    }()
    
    private lazy var textDetectionButton: UIBarButtonItem = {
        let image = UIImage(systemName: "text.viewfinder")
        let button = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(toggleTextDetection))
        button.tintColor = .black  // Black for visibility on light background
        return button
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let activityIndicator = UIActivityIndicatorView(style: .gray)
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        return activityIndicator
    }()
    
    /// Helper function to get timestamp for logging
    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    // MARK: - Life Cycle

    override public func viewDidLoad() {
        super.viewDidLoad()

        title = nil
        view.backgroundColor = UIColor.black

        setupViews()
        setupNavigationBar()
        setupConstraints()

        captureSessionManager = CaptureSessionManager(videoPreviewLayer: videoPreviewLayer, delegate: self)

        originalBarStyle = navigationController?.navigationBar.barStyle

        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: Notification.Name.AVCaptureDeviceSubjectAreaDidChange, object: nil)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setNeedsStatusBarAppearanceUpdate()

        CaptureSession.current.isEditing = false
        quadView.removeQuadrilateral()
        captureSessionManager?.start()
        UIApplication.shared.isIdleTimerDisabled = true

        navigationController?.navigationBar.barStyle = .blackTranslucent
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        videoPreviewLayer.frame = view.layer.bounds
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false

        navigationController?.navigationBar.isTranslucent = false
        navigationController?.navigationBar.barStyle = originalBarStyle ?? .default
        captureSessionManager?.stop()
        guard let device = AVCaptureDevice.default(for: AVMediaType.video) else { return }
        if device.torchMode == .on {
            toggleFlash()
        }
    }

    // MARK: - Setups

    private func setupViews() {
        view.backgroundColor = .darkGray
        view.layer.addSublayer(videoPreviewLayer)
        quadView.translatesAutoresizingMaskIntoConstraints = false
        quadView.editable = false
        view.addSubview(quadView)
        view.addSubview(cancelButton)
        view.addSubview(shutterButton)
        view.addSubview(activityIndicator)
        
        // Add new UI elements (matching screenshot layout)
        view.addSubview(galleryButton)
        view.addSubview(thumbnailButton)
        view.addSubview(thumbnailBadge)  // Add to view, not button, to prevent clipping
    }

    private func setupNavigationBar() {
        navigationItem.setLeftBarButton(flashButton, animated: false)
        navigationItem.setRightBarButtonItems([autoScanButton, textDetectionButton], animated: false)

        if UIImagePickerController.isFlashAvailable(for: .rear) == false {
            let flashOffImage = UIImage(systemName: "bolt.slash.fill", named: "flashUnavailable", in: Bundle(for: ScannerViewController.self), compatibleWith: nil)
            flashButton.image = flashOffImage
            flashButton.tintColor = UIColor.lightGray
        }
        
        // Update text detection button appearance
        updateTextDetectionButton()
    }

    private func setupConstraints() {
        var quadViewConstraints = [NSLayoutConstraint]()
        var cancelButtonConstraints = [NSLayoutConstraint]()
        var shutterButtonConstraints = [NSLayoutConstraint]()
        var activityIndicatorConstraints = [NSLayoutConstraint]()

        quadViewConstraints = [
            quadView.topAnchor.constraint(equalTo: view.topAnchor),
            view.bottomAnchor.constraint(equalTo: quadView.bottomAnchor),
            view.trailingAnchor.constraint(equalTo: quadView.trailingAnchor),
            quadView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        ]

        shutterButtonConstraints = [
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.widthAnchor.constraint(equalToConstant: 65.0),
            shutterButton.heightAnchor.constraint(equalToConstant: 65.0)
        ]

        activityIndicatorConstraints = [
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ]

        if #available(iOS 11.0, *) {
            // Position cancel button at top-left to avoid overlap with gallery button
            cancelButtonConstraints = [
                cancelButton.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 16.0),
                cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16.0)
            ]

            let shutterButtonBottomConstraint = view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: shutterButton.bottomAnchor, constant: 8.0)
            shutterButtonConstraints.append(shutterButtonBottomConstraint)
        } else {
            cancelButtonConstraints = [
                cancelButton.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 16.0),
                cancelButton.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor, constant: 16.0)
            ]

            let shutterButtonBottomConstraint = view.bottomAnchor.constraint(equalTo: shutterButton.bottomAnchor, constant: 8.0)
            shutterButtonConstraints.append(shutterButtonBottomConstraint)
        }

        // New UI elements constraints (matching screenshot layout)
        var galleryButtonConstraints = [NSLayoutConstraint]()
        var thumbnailButtonConstraints = [NSLayoutConstraint]()
        var thumbnailBadgeConstraints = [NSLayoutConstraint]()
        
        // Align gallery and thumbnail buttons vertically with shutter button
        galleryButtonConstraints = [
            galleryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            galleryButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor), // Align vertically
            galleryButton.widthAnchor.constraint(equalToConstant: 60),
            galleryButton.heightAnchor.constraint(equalToConstant: 60)
        ]
        
        thumbnailButtonConstraints = [
            view.trailingAnchor.constraint(equalTo: thumbnailButton.trailingAnchor, constant: 40),
            thumbnailButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor), // Align vertically
            thumbnailButton.widthAnchor.constraint(equalToConstant: 60),
            thumbnailButton.heightAnchor.constraint(equalToConstant: 60)
        ]
        
        // Fix badge positioning - position outside the button so it's not clipped
        thumbnailBadgeConstraints = [
            thumbnailBadge.topAnchor.constraint(equalTo: thumbnailButton.topAnchor, constant: -8),
            thumbnailBadge.trailingAnchor.constraint(equalTo: thumbnailButton.trailingAnchor, constant: 8),
            thumbnailBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
            thumbnailBadge.heightAnchor.constraint(equalToConstant: 24)
        ]
        
        NSLayoutConstraint.activate(quadViewConstraints + cancelButtonConstraints + shutterButtonConstraints + activityIndicatorConstraints + galleryButtonConstraints + thumbnailButtonConstraints + thumbnailBadgeConstraints)
    }

    // MARK: - Tap to Focus

    /// Called when the AVCaptureDevice detects that the subject area has changed significantly. When it's called, we reset the focus so the camera is no longer out of focus.
    @objc private func subjectAreaDidChange() {
        /// Reset the focus and exposure back to automatic
        do {
            try CaptureSession.current.resetFocusToAuto()
        } catch {
            let error = ImageScannerControllerError.inputDevice
            guard let captureSessionManager else { return }
            captureSessionManager.delegate?.captureSessionManager(captureSessionManager, didFailWithError: error)
            return
        }

        /// Remove the focus rectangle if one exists
        CaptureSession.current.removeFocusRectangleIfNeeded(focusRectangle, animated: true)
    }

    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)

        guard  let touch = touches.first else { return }
        let touchPoint = touch.location(in: view)
        let convertedTouchPoint: CGPoint = videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: touchPoint)

        CaptureSession.current.removeFocusRectangleIfNeeded(focusRectangle, animated: false)

        focusRectangle = FocusRectangleView(touchPoint: touchPoint)
        view.addSubview(focusRectangle)

        do {
            try CaptureSession.current.setFocusPointToTapPoint(convertedTouchPoint)
        } catch {
            let error = ImageScannerControllerError.inputDevice
            guard let captureSessionManager else { return }
            captureSessionManager.delegate?.captureSessionManager(captureSessionManager, didFailWithError: error)
            return
        }
    }

    // MARK: - Actions

    @objc private func captureImage(_ sender: UIButton) {
        (navigationController as? ImageScannerController)?.flashToBlack()
        shutterButton.isUserInteractionEnabled = false
        captureSessionManager?.capturePhoto()
    }

    @objc private func toggleAutoScan() {
        if CaptureSession.current.isAutoScanEnabled {
            CaptureSession.current.isAutoScanEnabled = false
            autoScanButton.title = NSLocalizedString("wescan.scanning.manual", tableName: nil, bundle: Bundle(for: ScannerViewController.self), value: "Manual", comment: "The manual button state")
        } else {
            CaptureSession.current.isAutoScanEnabled = true
            autoScanButton.title = NSLocalizedString("wescan.scanning.auto", tableName: nil, bundle: Bundle(for: ScannerViewController.self), value: "Auto", comment: "The auto button state")
        }
    }

    @objc private func toggleFlash() {
        let state = CaptureSession.current.toggleFlash()

        let flashImage = UIImage(systemName: "bolt.fill", named: "flash", in: Bundle(for: ScannerViewController.self), compatibleWith: nil)
        let flashOffImage = UIImage(systemName: "bolt.slash.fill", named: "flashUnavailable", in: Bundle(for: ScannerViewController.self), compatibleWith: nil)

        switch state {
        case .on:
            flashEnabled = true
            flashButton.image = flashImage
            flashButton.tintColor = .yellow
        case .off:
            flashEnabled = false
            flashButton.image = flashImage
            flashButton.tintColor = .white
        case .unknown, .unavailable:
            flashEnabled = false
            flashButton.image = flashOffImage
            flashButton.tintColor = UIColor.lightGray
        }
    }

    @objc private func toggleTextDetection() {
        guard let captureSessionManager = captureSessionManager else { return }
        captureSessionManager.useTextBasedDetection.toggle()
        updateTextDetectionButton()
        
        let statusText = captureSessionManager.useTextBasedDetection ? "Text+Vision" : "Vision Only"
        print("📸📸📸 TextDetection: Switched to \(statusText) detection mode")
    }
    
    private func updateTextDetectionButton() {
        guard let captureSessionManager = captureSessionManager else { return }
        
        if captureSessionManager.useTextBasedDetection {
            textDetectionButton.tintColor = UIColor(red: 255/255, green: 74/255, blue: 28/255, alpha: 1.0)  // Active orange (#FF4A1C)
        } else {
            textDetectionButton.tintColor = .black  // Inactive black color
        }
    }

    @objc private func cancelImageScannerController() {
        guard let imageScannerController = navigationController as? ImageScannerController else { return }
        imageScannerController.imageScannerDelegate?.imageScannerControllerDidCancel(imageScannerController)
    }
    
    // MARK: - New UI Actions
    
    @objc private func galleryButtonTapped() {
        guard let imageScannerController = navigationController as? ImageScannerController else { return }
        imageScannerController.presentGalleryPicker()
    }
    
    @objc private func thumbnailButtonTapped() {
        guard let imageScannerController = navigationController as? ImageScannerController else { return }
        
        // Navigate to thumbnail summary if we have scanned pages
        if imageScannerController.scanResults.count > 0 {
            imageScannerController.showThumbnailSummary()
        }
    }
    
    /// Update thumbnail button with latest scan preview and count badge
    private func updateThumbnailButton() {
        guard let imageScannerController = navigationController as? ImageScannerController else { return }
        
        let scanCount = imageScannerController.scanResults.count
        
        if scanCount > 0 {
            // Show badge with count
            thumbnailBadge.text = "\(scanCount)"
            thumbnailBadge.isHidden = false
            
            // Update thumbnail image with latest scan
            if let latestScan = imageScannerController.scanResults.last {
                let thumbnailImage = latestScan.croppedScan.image
                
                // Create a scaled thumbnail
                let imageView = UIImageView(image: thumbnailImage)
                imageView.contentMode = .scaleAspectFill
                imageView.frame = thumbnailButton.bounds
                imageView.clipsToBounds = true
                thumbnailButton.addSubview(imageView)
                thumbnailButton.sendSubviewToBack(imageView)
            }
        } else {
            thumbnailBadge.isHidden = true
        }
    }

}

extension ScannerViewController: RectangleDetectionDelegateProtocol {
    func captureSessionManager(_ captureSessionManager: CaptureSessionManager, didFailWithError error: Error) {

        activityIndicator.stopAnimating()
        shutterButton.isUserInteractionEnabled = true

        guard let imageScannerController = navigationController as? ImageScannerController else { return }
        imageScannerController.imageScannerDelegate?.imageScannerController(imageScannerController, didFailWithError: error)
    }

    func didStartCapturingPicture(for captureSessionManager: CaptureSessionManager) {
        activityIndicator.startAnimating()
        captureSessionManager.stop()
        shutterButton.isUserInteractionEnabled = false
    }

    func captureSessionManager(_ captureSessionManager: CaptureSessionManager, didCapturePicture picture: UIImage, withQuad quad: Quadrilateral?) {
        activityIndicator.stopAnimating()

        print("📸📸📸 Scanner: Processing captured image - size: \(picture.size), orientation: \(picture.imageOrientation.rawValue)")
        
        // Run DeepLabV3 detection on the captured high-res image to get accurate quad and mask
        guard let ciImage = CIImage(image: picture) else {
            print("❌ Scanner: Failed to create CIImage from captured picture")
            shutterButton.isUserInteractionEnabled = true
            return
        }
        
        let cgOrientation = CGImagePropertyOrientation(picture.imageOrientation)
        
        if #available(iOS 15.0, *) {
            // Run full DeepLabV3 detection on captured image (same as gallery flow)
            let renderStart = CACurrentMediaTime()
            CoreMLSegmentationDetector.segmentPage(forImage: ciImage, orientation: cgOrientation) { [weak self] result in
                guard let self = self else { return }
                
                let callbackTime = (CACurrentMediaTime() - renderStart) * 1000
                print("[\(self.timestamp())] 📸 Scanner: Segmentation callback after \(String(format: "%.0f", callbackTime))ms")
                
                var detectedQuad: Quadrilateral?
                var maskImage: UIImage?
                
                if let result = result, let quad = CoreMLSegmentationDetector.convertToQuadrilateral(from: result) {
                    print("[\(self.timestamp())] 📸 Scanner: DeepLabV3 detected quad on captured image")
                    let orientedImage = ciImage.oriented(forExifOrientation: Int32(cgOrientation.rawValue))
                    detectedQuad = quad.toCartesian(withHeight: orientedImage.extent.height)
                    
                    // Check if mask rendering is enabled in config
                    if CoreMLSegmentationDetector.shouldRenderMaskOverlay {
                        let maskStart = CACurrentMediaTime()
                        print("[\(self.timestamp())] 📸 Scanner: Rendering mask overlay (this may take ~4 seconds)...")
                        maskImage = CoreMLSegmentationDetector.renderMaskImage(
                            originalSize: picture.size,
                            mask: result.mask,
                            threshold: 0.5,
                            color: .systemBlue,
                            alpha: 0.45
                        )
                        let maskTime = (CACurrentMediaTime() - maskStart) * 1000
                        print("[\(self.timestamp())] 📸 Scanner: Mask rendering complete (\(String(format: "%.0f", maskTime))ms)")
                    } else {
                        print("[\(self.timestamp())] 📸 Scanner: Mask rendering disabled (config.renderMaskOverlay = false)")
                    }
                } else {
                    print("[\(self.timestamp())] 📸 Scanner: No quad detected by DeepLabV3, using live preview quad if available")
                    detectedQuad = quad
                }
                
                // Process the captured image with detected quad and optional mask
                self.processCapturedImage(picture, detectedQuad: detectedQuad, maskImage: maskImage)
            }
        } else {
            // iOS < 15: Use the quad from live preview
            print("[\(self.timestamp())] 📸 Scanner: iOS < 15, using live preview quad")
            self.processCapturedImage(picture, detectedQuad: quad, maskImage: nil)
        }
    }
    
    private func processCapturedImage(_ picture: UIImage, detectedQuad: Quadrilateral?, maskImage: UIImage?) {
        let startTime = CACurrentMediaTime()
        let timestamp = self.timestamp()
        print("[\(timestamp)] 📸 Scanner: processCapturedImage START - image size: \(picture.size)")
        
        guard let imageScannerController = navigationController as? ImageScannerController else {
            print("[\(self.timestamp())] ❌ Scanner: Failed to get ImageScannerController")
            shutterButton.isUserInteractionEnabled = true
            return
        }
        
        // Auto-crop the image using detected quad (same logic as EditScanViewController)
        let originalScan = ImageScannerScan(image: picture)
        print("[\(self.timestamp())] 📸 Scanner: Created originalScan")
        
        let croppedScan: ImageScannerScan
        let finalQuad: Quadrilateral?
        
        if let quad = detectedQuad,
           let ciImage = CIImage(image: picture) {
            
            print("[\(self.timestamp())] 🔷🔷🔷 AUTO-CROP (Live Camera)")
            print("[\(self.timestamp())] 🔷 Input image size: \(picture.size)")
            print("[\(self.timestamp())] 🔷 Input image orientation: \(picture.imageOrientation.rawValue)")
            
            let cgOrientation = CGImagePropertyOrientation(picture.imageOrientation)
            let orientedImage = ciImage.oriented(forExifOrientation: Int32(cgOrientation.rawValue))
            
            // Convert quad to Cartesian coordinates for cropping
            var cartesianQuad = quad.toCartesian(withHeight: picture.size.height)
            cartesianQuad.reorganize()
            
            print("[\(self.timestamp())] 🔷 Detected quad: TL=\(quad.topLeft), TR=\(quad.topRight), BR=\(quad.bottomRight), BL=\(quad.bottomLeft)")
            print("[\(self.timestamp())] 🔷 Cartesian quad: TL=\(cartesianQuad.topLeft), TR=\(cartesianQuad.topRight), BR=\(cartesianQuad.bottomRight), BL=\(cartesianQuad.bottomLeft)")
            
            let filteredImage = orientedImage.applyingFilter("CIPerspectiveCorrection", parameters: [
                "inputTopLeft": CIVector(cgPoint: cartesianQuad.bottomLeft),
                "inputTopRight": CIVector(cgPoint: cartesianQuad.bottomRight),
                "inputBottomLeft": CIVector(cgPoint: cartesianQuad.topLeft),
                "inputBottomRight": CIVector(cgPoint: cartesianQuad.topRight)
            ])
            
            let croppedImage = UIImage.from(ciImage: filteredImage)
            croppedScan = ImageScannerScan(image: croppedImage)
            finalQuad = quad  // Save original quad for potential editing later
            
            print("[\(self.timestamp())] 🔷 Output cropped image size: \(croppedImage.size)")
            print("[\(self.timestamp())] 🔷 AUTO-CROP COMPLETE")
            print("[\(self.timestamp())] 🔷🔷🔷")
        } else {
            print("[\(self.timestamp())] 📸 Scanner: No quad detected, using original image")
            croppedScan = originalScan
            finalQuad = nil
        }
        
        // Create scan results with cropped image
        let scanResult = ImageScannerResults(
            detectedRectangle: finalQuad,
            originalScan: originalScan,
            croppedScan: croppedScan,
            enhancedScan: nil,
            overlayImage: maskImage
        )
        
        // Add to results and stay on camera for next scan
        imageScannerController.addScanResult(scanResult)
        
        // Update thumbnail button with new scan count and preview
        updateThumbnailButton()
        
        let totalTime = (CACurrentMediaTime() - startTime) * 1000
        print("[\(self.timestamp())] 📸 Scanner: Auto-crop and add complete (\(String(format: "%.0f", totalTime))ms)")
        print("[\(self.timestamp())] 📸 Scanner: Returning to camera for next scan")
        
        shutterButton.isUserInteractionEnabled = true
    }

    func captureSessionManager(_ captureSessionManager: CaptureSessionManager, didDetectQuad quad: Quadrilateral?, _ imageSize: CGSize) {
        guard let quad else {
            // If no quad has been detected, we remove the currently displayed on on the quadView.
            quadView.removeQuadrilateral()
            return
        }

        let timestamp = DateFormatter()
        timestamp.dateFormat = "HH:mm:ss.SSS"
        let ts = timestamp.string(from: Date())
        
        print("[\(ts)] 📸 Scanner: didDetectQuad - imageSize: \(imageSize)")
        print("[\(ts)] 📸 Scanner: Quad - TL(\(quad.topLeft.x), \(quad.topLeft.y)) BR(\(quad.bottomRight.x), \(quad.bottomRight.y))")

        // ImageSize from DeepLabV3 is already in the correct orientation (portrait)
        // So we DON'T need to swap width/height like we did for camera buffer coordinates
        let scaleTransform = CGAffineTransform.scaleTransform(forSize: imageSize, aspectFillInSize: quadView.bounds.size)
        let scaledImageSize = imageSize.applying(scaleTransform)

        print("[\(ts)] 📸 Scanner: Scale: \(scaleTransform.a), scaled image: \(scaledImageSize)")

        let rotationTransform = CGAffineTransform(rotationAngle: CGFloat.pi / 2.0)

        let imageBounds = CGRect(origin: .zero, size: scaledImageSize).applying(rotationTransform)

        let translationTransform = CGAffineTransform.translateTransform(fromCenterOfRect: imageBounds, toCenterOfRect: quadView.bounds)

        let transforms = [scaleTransform, rotationTransform, translationTransform]

        let transformedQuad = quad.applyTransforms(transforms)

        print("[\(ts)] 📸 Scanner: Transformed quad - TL(\(transformedQuad.topLeft.x), \(transformedQuad.topLeft.y)) BR(\(transformedQuad.bottomRight.x), \(transformedQuad.bottomRight.y))")

        quadView.drawQuadrilateral(quad: transformedQuad, animated: true)
    }

}
