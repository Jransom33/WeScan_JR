//
//  ImageScannerController.swift
//  WeScan
//
//  Created by Boris Emorine on 2/12/18.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import AVFoundation
import UIKit
import CoreImage
import Vision
import CoreML

/// A set of methods that your delegate object must implement to interact with the image scanner interface.
public protocol ImageScannerControllerDelegate: NSObjectProtocol {

    /// Tells the delegate that the user scanned a document.
    ///
    /// - Parameters:
    ///   - scanner: The scanner controller object managing the scanning interface.
    ///   - results: The results of the user scanning with the camera.
    /// - Discussion: Your delegate's implementation of this method should dismiss the image scanner controller.
    func imageScannerController(_ scanner: ImageScannerController, didFinishScanningWithResults results: ImageScannerResults)

    /// Tells the delegate that the user cancelled the scan operation.
    ///
    /// - Parameters:
    ///   - scanner: The scanner controller object managing the scanning interface.
    /// - Discussion: Your delegate's implementation of this method should dismiss the image scanner controller.
    func imageScannerControllerDidCancel(_ scanner: ImageScannerController)

    /// Tells the delegate that an error occurred during the user's scanning experience.
    ///
    /// - Parameters:
    ///   - scanner: The scanner controller object managing the scanning interface.
    ///   - error: The error that occurred.
    func imageScannerController(_ scanner: ImageScannerController, didFailWithError error: Error)
}

/// Enhanced delegate protocol for multi-page document scanning.
public protocol MultiPageImageScannerControllerDelegate: NSObjectProtocol {
    
    /// Tells the delegate that the user finished scanning multiple pages.
    ///
    /// - Parameters:
    ///   - scanner: The scanner controller object managing the scanning interface.
    ///   - results: Array of results from all scanned pages.
    /// - Discussion: Your delegate's implementation of this method should dismiss the image scanner controller.
    func imageScannerController(_ scanner: ImageScannerController, didFinishScanningWithMultipleResults results: [ImageScannerResults])
    
    /// Tells the delegate that the user cancelled the scan operation.
    ///
    /// - Parameters:
    ///   - scanner: The scanner controller object managing the scanning interface.
    /// - Discussion: Your delegate's implementation of this method should dismiss the image scanner controller.
    func imageScannerControllerDidCancel(_ scanner: ImageScannerController)
    
    /// Tells the delegate that an error occurred during the user's scanning experience.
    ///
    /// - Parameters:
    ///   - scanner: The scanner controller object managing the scanning interface.
    ///   - error: The error that occurred.
    func imageScannerController(_ scanner: ImageScannerController, didFailWithError error: Error)
}

/// A view controller that manages the full flow for scanning documents.
/// The `ImageScannerController` class is meant to be presented. It consists of a series of 3 different screens which guide the user:
/// 1. Uses the camera to capture an image with a rectangle that has been detected.
/// 2. Edit the detected rectangle.
/// 3. Review the cropped down version of the rectangle.
public final class ImageScannerController: UINavigationController {
    
    // MARK: - CoreML Configuration
    
    /// Configure WeScan with a CoreML model for corner detection
    /// This must be called before using the scanner
    /// - Parameter model: The CoreML model to use for corner detection
    @available(iOS 11.0, *)
    public static func configure(with model: MLModel) throws {
        try CoreMLRectangleDetector.configure(with: model)
    }
    
    /// Configure WeScan with a CoreML model from bundle
    /// - Parameters:
    ///   - modelName: Name of the model file (without extension)
    ///   - bundle: Bundle containing the model (defaults to main bundle)
    @available(iOS 11.0, *)
    public static func configure(modelName: String, in bundle: Bundle = Bundle.main) throws {
        try CoreMLRectangleDetector.configure(modelName: modelName, in: bundle)
    }
    
    /// Check if WeScan has been configured with a CoreML model
    @available(iOS 11.0, *)
    public static var isConfigured: Bool {
        return CoreMLRectangleDetector.isConfigured
    }

    // MARK: - Delegates
    
    /// The object that acts as the delegate of the `ImageScannerController`.
    public weak var imageScannerDelegate: ImageScannerControllerDelegate?
    
    /// The object that acts as the multi-page delegate of the `ImageScannerController`.
    public weak var multiPageDelegate: MultiPageImageScannerControllerDelegate?
    
    /// Enables multi-page scanning mode where users can capture multiple documents.
    public var isMultiPageScanningEnabled: Bool = false
    
    /// Array to store multiple scan results when in multi-page mode.
    internal var scanResults: [ImageScannerResults] = []
    
    /// Thumbnail views displayed in the bottom-left corner for multi-page mode.
    private var thumbnailContainerView: UIView?
    private var thumbnailScrollView: UIScrollView?
    private var thumbnailStackView: UIStackView?
    
    /// Save/Done button for multi-page mode.
    private var saveDoneButton: UIButton?

    // MARK: - Life Cycle

    /// A black UIView, used to quickly display a black screen when the shutter button is presseed.
    internal let blackFlashView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(white: 0.0, alpha: 0.5)
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    public required init(image: UIImage? = nil, delegate: ImageScannerControllerDelegate? = nil) {
        super.init(rootViewController: ScannerViewController())

        self.imageScannerDelegate = delegate

        if #available(iOS 13.0, *) {
            navigationBar.tintColor = .label
        } else {
            navigationBar.tintColor = .black
        }
        navigationBar.isTranslucent = false
        self.view.addSubview(blackFlashView)
        setupConstraints()

        // If an image was passed in by the host app (e.g. picked from the photo library), use it instead of the document scanner.
        if let image {
            detect(image: image) { [weak self] detectedQuad in
                guard let self else { return }
                let editViewController = EditScanViewController(image: image, quad: detectedQuad, rotateImage: false)
                self.setViewControllers([editViewController], animated: false)
            }
        }
    }
    
    /// Initializer for multi-page scanning mode.
    public convenience init(multiPageDelegate: MultiPageImageScannerControllerDelegate) {
        self.init()
        self.multiPageDelegate = multiPageDelegate
        self.isMultiPageScanningEnabled = true
        setupMultiPageUI()
    }

    override public init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func detect(image: UIImage, completion: @escaping (Quadrilateral?) -> Void) {
        // Whether or not we detect a quad, present the edit view controller after attempting to detect a quad.
        // *** Vision *requires* a completion block to detect rectangles, but it's instant.
        // *** When using Vision, we'll present the normal edit view controller first, then present the updated edit view controller later.

        guard let ciImage = CIImage(image: image) else { return }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let orientedImage = ciImage.oriented(forExifOrientation: Int32(orientation.rawValue))

        if #available(iOS 11.0, *) {
            // Try CoreML-based corner detection first, fall back to Vision if model not available
            CoreMLRectangleDetector.rectangle(forImage: ciImage, orientation: orientation) { quad in
                if quad == nil {
                    // Fall back to traditional Vision detection if CoreML model not available
                    VisionRectangleDetector.rectangle(forImage: ciImage, orientation: orientation) { fallbackQuad in
                        let detectedQuad = fallbackQuad?.toCartesian(withHeight: orientedImage.extent.height)
                        completion(detectedQuad)
                    }
                } else {
                    let detectedQuad = quad?.toCartesian(withHeight: orientedImage.extent.height)
                    completion(detectedQuad)
                }
            }
        } else {
            // Use the CIRectangleDetector on iOS 10 to attempt to find a rectangle from the initial image.
            let detectedQuad = CIRectangleDetector.rectangle(forImage: ciImage)?.toCartesian(withHeight: orientedImage.extent.height)
            completion(detectedQuad)
        }
    }

    public func useImage(image: UIImage) {
        guard topViewController is ScannerViewController else { return }

        detect(image: image) { [weak self] detectedQuad in
            guard let self else { return }
            let editViewController = EditScanViewController(image: image, quad: detectedQuad, rotateImage: false)
            self.setViewControllers([editViewController], animated: true)
        }
    }

    public func resetScanner() {
        setViewControllers([ScannerViewController()], animated: true)
    }

    private func setupConstraints() {
        let blackFlashViewConstraints = [
            blackFlashView.topAnchor.constraint(equalTo: view.topAnchor),
            blackFlashView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.bottomAnchor.constraint(equalTo: blackFlashView.bottomAnchor),
            view.trailingAnchor.constraint(equalTo: blackFlashView.trailingAnchor)
        ]

        NSLayoutConstraint.activate(blackFlashViewConstraints)
    }

    internal func flashToBlack() {
        view.bringSubviewToFront(blackFlashView)
        blackFlashView.isHidden = false
        let flashDuration = DispatchTime.now() + 0.05
        DispatchQueue.main.asyncAfter(deadline: flashDuration) {
            self.blackFlashView.isHidden = true
        }
    }
    
    // MARK: - Multi-Page Functionality
    
    /// Sets up the UI elements for multi-page scanning mode.
    private func setupMultiPageUI() {
        setupThumbnailContainer()
        setupSaveDoneButton()
    }
    
    /// Sets up the thumbnail container in the bottom-left corner.
    private func setupThumbnailContainer() {
        // Main container view
        thumbnailContainerView = UIView()
        thumbnailContainerView?.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        thumbnailContainerView?.layer.cornerRadius = 8
        thumbnailContainerView?.translatesAutoresizingMaskIntoConstraints = false
        
        guard let containerView = thumbnailContainerView else { return }
        view.addSubview(containerView)
        
        // Scroll view for horizontal scrolling
        thumbnailScrollView = UIScrollView()
        thumbnailScrollView?.showsHorizontalScrollIndicator = false
        thumbnailScrollView?.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(thumbnailScrollView!)
        
        // Stack view to arrange thumbnails
        thumbnailStackView = UIStackView()
        thumbnailStackView?.axis = .horizontal
        thumbnailStackView?.spacing = 8
        thumbnailStackView?.translatesAutoresizingMaskIntoConstraints = false
        thumbnailScrollView?.addSubview(thumbnailStackView!)
        
        // Constraints
        NSLayoutConstraint.activate([
            // Container constraints
            containerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            containerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            containerView.heightAnchor.constraint(equalToConstant: 80),
            containerView.widthAnchor.constraint(lessThanOrEqualToConstant: 240),
            
            // Scroll view constraints
            thumbnailScrollView!.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            thumbnailScrollView!.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            thumbnailScrollView!.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            thumbnailScrollView!.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
            
            // Stack view constraints
            thumbnailStackView!.topAnchor.constraint(equalTo: thumbnailScrollView!.topAnchor),
            thumbnailStackView!.leadingAnchor.constraint(equalTo: thumbnailScrollView!.leadingAnchor),
            thumbnailStackView!.trailingAnchor.constraint(equalTo: thumbnailScrollView!.trailingAnchor),
            thumbnailStackView!.bottomAnchor.constraint(equalTo: thumbnailScrollView!.bottomAnchor),
            thumbnailStackView!.heightAnchor.constraint(equalTo: thumbnailScrollView!.heightAnchor)
        ])
        
        // Initially hide the container
        containerView.isHidden = true
    }
    
    /// Sets up the save/done button in the bottom-right corner.
    private func setupSaveDoneButton() {
        saveDoneButton = UIButton(type: .system)
        saveDoneButton?.setTitle("Done", for: .normal)
        saveDoneButton?.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        saveDoneButton?.setTitleColor(.white, for: .normal)
        saveDoneButton?.backgroundColor = UIColor.systemBlue
        saveDoneButton?.layer.cornerRadius = 8
        saveDoneButton?.translatesAutoresizingMaskIntoConstraints = false
        saveDoneButton?.addTarget(self, action: #selector(saveDoneButtonTapped), for: .touchUpInside)
        
        guard let button = saveDoneButton else { return }
        view.addSubview(button)
        
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            button.widthAnchor.constraint(equalToConstant: 80),
            button.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        // Initially hide the button
        button.isHidden = true
    }
    
    /// Adds a new scan result and updates the thumbnail display.
    internal func addScanResult(_ result: ImageScannerResults) {
        scanResults.append(result)
        addThumbnailForResult(result, at: scanResults.count - 1)
        updateUIForMultipleScans()
        
        print("📸📸📸 MultiScan: Added scan \(scanResults.count), showing thumbnail summary")
        
        // Show thumbnail summary instead of automatically returning to camera
        DispatchQueue.main.async { [weak self] in
            self?.showThumbnailSummary()
        }
    }
    
    /// Creates and adds a thumbnail for a scan result.
    private func addThumbnailForResult(_ result: ImageScannerResults, at index: Int) {
        let thumbnailImageView = UIImageView(image: result.croppedScan.image)
        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true
        thumbnailImageView.layer.cornerRadius = 4
        thumbnailImageView.layer.borderWidth = 2
        thumbnailImageView.layer.borderColor = UIColor.white.cgColor
        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        
        // Add tap gesture for editing
        thumbnailImageView.isUserInteractionEnabled = true
        thumbnailImageView.tag = index
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(thumbnailTapped(_:)))
        thumbnailImageView.addGestureRecognizer(tapGesture)
        
        // Add page number label
        let pageLabel = UILabel()
        pageLabel.text = "\\(index + 1)"
        pageLabel.textColor = .white
        pageLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        pageLabel.textAlignment = .center
        pageLabel.font = UIFont.boldSystemFont(ofSize: 12)
        pageLabel.layer.cornerRadius = 8
        pageLabel.clipsToBounds = true
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        thumbnailImageView.addSubview(pageLabel)
        thumbnailStackView?.addArrangedSubview(thumbnailImageView)
        
        NSLayoutConstraint.activate([
            thumbnailImageView.widthAnchor.constraint(equalToConstant: 50),
            thumbnailImageView.heightAnchor.constraint(equalToConstant: 64),
            
            pageLabel.topAnchor.constraint(equalTo: thumbnailImageView.topAnchor, constant: 2),
            pageLabel.trailingAnchor.constraint(equalTo: thumbnailImageView.trailingAnchor, constant: -2),
            pageLabel.widthAnchor.constraint(equalToConstant: 16),
            pageLabel.heightAnchor.constraint(equalToConstant: 16)
        ])
    }
    
    /// Updates UI elements when multiple scans are present.
    private func updateUIForMultipleScans() {
        if scanResults.count > 0 {
            thumbnailContainerView?.isHidden = false
            saveDoneButton?.isHidden = false
            
            // Update done button text
            saveDoneButton?.setTitle("Done (\\(scanResults.count))", for: .normal)
            
            // Scroll to show the latest thumbnail
            DispatchQueue.main.async { [weak self] in
                guard let scrollView = self?.thumbnailScrollView else { return }
                let rightOffset = CGPoint(x: scrollView.contentSize.width - scrollView.bounds.width, y: 0)
                if rightOffset.x > 0 {
                    scrollView.setContentOffset(rightOffset, animated: true)
                }
            }
        }
    }
    
    /// Handles thumbnail tap for editing.
    @objc private func thumbnailTapped(_ gesture: UITapGestureRecognizer) {
        guard let imageView = gesture.view as? UIImageView else { return }
        let index = imageView.tag
        
        guard index < scanResults.count else { return }
        
        print("📸📸📸 MultiScan: Editing scan \\(index + 1)")
        
        let result = scanResults[index]
        let editViewController = EditScanViewController(
            image: result.originalScan.image,
            quad: result.detectedRectangle,
            rotateImage: false
        )
        editViewController.editingIndex = index
        setViewControllers([editViewController], animated: true)
    }
    
    /// Handles save/done button tap.
    @objc private func saveDoneButtonTapped() {
        print("📸📸📸 MultiScan: Completed with \\(scanResults.count) scans")
        
        if scanResults.isEmpty {
            multiPageDelegate?.imageScannerControllerDidCancel(self)
        } else {
            multiPageDelegate?.imageScannerController(self, didFinishScanningWithMultipleResults: scanResults)
        }
    }
    
    /// Updates an existing scan result after editing.
    internal func updateScanResult(_ result: ImageScannerResults, at index: Int) {
        guard index < scanResults.count else { return }
        
        scanResults[index] = result
        
        // Update the thumbnail
        if let stackView = thumbnailStackView,
           index < stackView.arrangedSubviews.count,
           let thumbnailImageView = stackView.arrangedSubviews[index] as? UIImageView {
            thumbnailImageView.image = result.croppedScan.image
        }
        
        print("📸📸📸 MultiScan: Updated scan \\(index + 1)")
    }
    
    // MARK: - New Thumbnail Summary Functionality
    
    /// Shows the thumbnail summary view controller
    internal func showThumbnailSummary() {
        let thumbnailSummaryVC = ThumbnailSummaryViewController()
        thumbnailSummaryVC.delegate = self
        thumbnailSummaryVC.setScanResults(scanResults)
        
        print("📸📸📸 ImageScanner: Showing thumbnail summary with \(scanResults.count) pages")
        pushViewController(thumbnailSummaryVC, animated: true)
    }
    
    /// Updates a scan result from the thumbnail summary edit flow
    internal func updateScanResultFromThumbnailSummary(_ result: ImageScannerResults, at index: Int) {
        guard index >= 0 && index < scanResults.count else { return }
        scanResults[index] = result
        
        print("📸📸📸 ImageScanner: Updated scan \(index + 1) from thumbnail edit")
        
        // Find and update the thumbnail summary if it's in the navigation stack
        for viewController in viewControllers {
            if let thumbnailSummaryVC = viewController as? ThumbnailSummaryViewController {
                thumbnailSummaryVC.updateScanResult(at: index, with: result)
                break
            }
        }
    }
}

/// Data structure containing information about a scan, including both the image and an optional PDF.
public struct ImageScannerScan {
    public enum ImageScannerError: Error {
        case failedToGeneratePDF
    }

    public var image: UIImage

    public func generatePDFData(completion: @escaping (Result<Data, ImageScannerError>) -> Void) {
        DispatchQueue.global(qos: .userInteractive).async {
            if let pdfData = self.image.pdfData() {
                completion(.success(pdfData))
            } else {
                completion(.failure(.failedToGeneratePDF))
            }
        }

    }

    mutating func rotate(by rotationAngle: Measurement<UnitAngle>) {
        guard rotationAngle.value != 0, rotationAngle.value != 360 else { return }
        image = image.rotated(by: rotationAngle) ?? image
    }
}

/// Data structure containing information about a scanning session.
/// Includes the original scan, cropped scan, detected rectangle, and whether the user selected the enhanced scan.
/// May also include an enhanced scan if no errors were encountered.
public struct ImageScannerResults {

    /// The original scan taken by the user, prior to the cropping applied by WeScan.
    public var originalScan: ImageScannerScan

    /// The deskewed and cropped scan using the detected rectangle, without any filters.
    public var croppedScan: ImageScannerScan

    /// The enhanced scan, passed through an Adaptive Thresholding function.
    /// This image will always be grayscale and may not always be available.
    public var enhancedScan: ImageScannerScan?

    /// Whether the user selected the enhanced scan or not.
    /// The `enhancedScan` may still be available even if it has not been selected by the user.
    public var doesUserPreferEnhancedScan: Bool

    /// The detected rectangle which was used to generate the `scannedImage`.
    public var detectedRectangle: Quadrilateral?

    init(
        detectedRectangle: Quadrilateral?,
        originalScan: ImageScannerScan,
        croppedScan: ImageScannerScan,
        enhancedScan: ImageScannerScan?,
        doesUserPreferEnhancedScan: Bool = false
    ) {
        self.detectedRectangle = detectedRectangle

        self.originalScan = originalScan
        self.croppedScan = croppedScan
        self.enhancedScan = enhancedScan

        self.doesUserPreferEnhancedScan = doesUserPreferEnhancedScan
    }
    
    /// Convenience initializer for simple scan results
    public init(originalScan: ImageScannerScan, croppedScan: ImageScannerScan, detectedRectangle: Quadrilateral?) {
        self.originalScan = originalScan
        self.croppedScan = croppedScan
        self.detectedRectangle = detectedRectangle
        self.enhancedScan = nil
        self.doesUserPreferEnhancedScan = false
    }
}
