//
//  EditScanViewController.swift
//  WeScan
//
//  Created by Boris Emorine on 2/12/18.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import AVFoundation
import UIKit

/// The `EditScanViewController` offers an interface for the user to edit the detected quadrilateral.
final class EditScanViewController: UIViewController {
    
    /// Index for editing existing scans in multi-page mode. Nil for new scans.
    var editingIndex: Int?

    private lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.clipsToBounds = true
        imageView.isOpaque = true
        imageView.image = image
        imageView.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var maskOverlayImageView: UIImageView = {
        let overlay = UIImageView()
        overlay.clipsToBounds = true
        overlay.isOpaque = false
        overlay.image = overlayImage
        overlay.backgroundColor = .clear
        overlay.contentMode = .scaleAspectFit
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.isUserInteractionEnabled = false
        return overlay
    }()

    private lazy var quadView: QuadrilateralView = {
        let quadView = QuadrilateralView()
        quadView.editable = true
        quadView.translatesAutoresizingMaskIntoConstraints = false
        return quadView
    }()

    private lazy var nextButton: UIBarButtonItem = {
        let title = NSLocalizedString("wescan.edit.button.next",
                                      tableName: nil,
                                      bundle: Bundle(for: EditScanViewController.self),
                                      value: "Next",
                                      comment: "A generic next button"
        )
        let button = UIBarButtonItem(title: title, style: .plain, target: self, action: #selector(pushReviewController))
        button.tintColor = navigationController?.navigationBar.tintColor
        return button
    }()

    private lazy var cancelButton: UIBarButtonItem = {
        let title = NSLocalizedString("wescan.scanning.cancel",
                                      tableName: nil,
                                      bundle: Bundle(for: EditScanViewController.self),
                                      value: "Cancel",
                                      comment: "A generic cancel button"
        )
        let button = UIBarButtonItem(title: title, style: .plain, target: self, action: #selector(cancelButtonTapped))
        button.tintColor = navigationController?.navigationBar.tintColor
        return button
    }()

    /// The image the quadrilateral was detected on.
    private let image: UIImage

    /// The detected quadrilateral that can be edited by the user. Uses the image's coordinates.
    private var quad: Quadrilateral

    /// Optional rendered segmentation mask to overlay during editing
    private let overlayImage: UIImage?

    private var zoomGestureController: ZoomGestureController!

    private var quadViewWidthConstraint = NSLayoutConstraint()
    private var quadViewHeightConstraint = NSLayoutConstraint()

    // MARK: - Life Cycle

    init(image: UIImage, quad: Quadrilateral?, overlayImage: UIImage? = nil, rotateImage: Bool = true) {
        let rotatedImage = rotateImage ? image.applyingPortraitOrientation() : image
        self.image = rotatedImage
        
        print("📸📸📸 EditScan INIT: Image orientation: \(image.imageOrientation.rawValue), size: \(image.size) -> rotated size: \(rotatedImage.size), rotateImage: \(rotateImage)")
        
        // Transform quad coordinates to match how the image is displayed
        if let quad = quad {
            print("📸📸📸 EditScan INIT: Quad from detector (Cartesian) - TL(\(quad.topLeft.x), \(quad.topLeft.y)) BR(\(quad.bottomRight.x), \(quad.bottomRight.y))")
            
            var transformedQuad = quad
            
            if !rotateImage {
                // When rotateImage is false, the image retains its orientation metadata
                // but the quad came in Cartesian coordinates (Y-flipped). We need to undo
                // the Cartesian conversion to match the display coordinate system.
                print("📸📸📸 EditScan INIT: rotateImage=false - converting Cartesian quad back to UIKit coords")
                transformedQuad = quad.toCartesian(withHeight: image.size.height)
            } else {
                // When rotateImage is true, the image was physically rotated based on orientation
                // We need to transform the quad to match the rotated image
                let originalSize = image.size
                
                switch image.imageOrientation {
                case .up:
                    // 180° rotation - flip both X and Y
                    print("📸📸📸 EditScan INIT: Orientation .up - applying 180° rotation (flip X and Y)")
                    transformedQuad = Quadrilateral(
                        topLeft: CGPoint(x: originalSize.width - quad.topLeft.x, y: originalSize.height - quad.topLeft.y),
                        topRight: CGPoint(x: originalSize.width - quad.topRight.x, y: originalSize.height - quad.topRight.y),
                        bottomRight: CGPoint(x: originalSize.width - quad.bottomRight.x, y: originalSize.height - quad.bottomRight.y),
                        bottomLeft: CGPoint(x: originalSize.width - quad.bottomLeft.x, y: originalSize.height - quad.bottomLeft.y)
                    )
                    
                case .right:
                    // 90° clockwise rotation: new_x = y, new_y = width - x
                    print("📸📸📸 EditScan INIT: Orientation .right - applying 90° rotation")
                    transformedQuad = Quadrilateral(
                        topLeft: CGPoint(x: quad.topLeft.y, y: originalSize.width - quad.topLeft.x),
                        topRight: CGPoint(x: quad.topRight.y, y: originalSize.width - quad.topRight.x),
                        bottomRight: CGPoint(x: quad.bottomRight.y, y: originalSize.width - quad.bottomRight.x),
                        bottomLeft: CGPoint(x: quad.bottomLeft.y, y: originalSize.width - quad.bottomLeft.x)
                    )
                    
                case .down:
                    // 180° rotation with flips
                    print("📸📸📸 EditScan INIT: Orientation .down - applying 180° rotation with flips")
                    transformedQuad = Quadrilateral(
                        topLeft: CGPoint(x: originalSize.width - quad.topLeft.x, y: originalSize.height - quad.topLeft.y),
                        topRight: CGPoint(x: originalSize.width - quad.topRight.x, y: originalSize.height - quad.topRight.y),
                        bottomRight: CGPoint(x: originalSize.width - quad.bottomRight.x, y: originalSize.height - quad.bottomRight.y),
                        bottomLeft: CGPoint(x: originalSize.width - quad.bottomLeft.x, y: originalSize.height - quad.bottomLeft.y)
                    )
                    
                case .left:
                    // No rotation needed
                    print("📸📸📸 EditScan INIT: Orientation .left - no transformation needed")
                    
                default:
                    print("📸📸📸 EditScan INIT: Orientation \(image.imageOrientation.rawValue) - no transformation")
                }
            }
            
            print("📸📸📸 EditScan INIT: Transformed quad for display - TL(\(transformedQuad.topLeft.x), \(transformedQuad.topLeft.y)) BR(\(transformedQuad.bottomRight.x), \(transformedQuad.bottomRight.y))")
            
            self.quad = transformedQuad
        } else {
            self.quad = EditScanViewController.defaultQuad(forImage: rotatedImage)
        }
        
        self.overlayImage = overlayImage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        setupViews()
        setupConstraints()
        title = NSLocalizedString("wescan.edit.title",
                                  tableName: nil,
                                  bundle: Bundle(for: EditScanViewController.self),
                                  value: "Edit Scan",
                                  comment: "The title of the EditScanViewController"
        )
        navigationItem.rightBarButtonItem = nextButton
        if let firstVC = self.navigationController?.viewControllers.first, firstVC == self {
            navigationItem.leftBarButtonItem = cancelButton
        } else {
            navigationItem.leftBarButtonItem = nil
        }

        zoomGestureController = ZoomGestureController(image: image, quadView: quadView)

        let touchDown = UILongPressGestureRecognizer(target: zoomGestureController, action: #selector(zoomGestureController.handle(pan:)))
        touchDown.minimumPressDuration = 0
        view.addGestureRecognizer(touchDown)
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        adjustQuadViewConstraints()
        displayQuad()
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Work around for an iOS 11.2 bug where UIBarButtonItems don't get back to their normal state after being pressed.
        navigationController?.navigationBar.tintAdjustmentMode = .normal
        navigationController?.navigationBar.tintAdjustmentMode = .automatic
    }

    // MARK: - Setups

    private func setupViews() {
        view.addSubview(imageView)
        view.addSubview(maskOverlayImageView)
        view.addSubview(quadView)
    }

    private func setupConstraints() {
        let imageViewConstraints = [
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: imageView.leadingAnchor)
        ]

        let overlayConstraints = [
            maskOverlayImageView.topAnchor.constraint(equalTo: imageView.topAnchor),
            maskOverlayImageView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            imageView.bottomAnchor.constraint(equalTo: maskOverlayImageView.bottomAnchor),
            imageView.trailingAnchor.constraint(equalTo: maskOverlayImageView.trailingAnchor)
        ]

        quadViewWidthConstraint = quadView.widthAnchor.constraint(equalToConstant: 0.0)
        quadViewHeightConstraint = quadView.heightAnchor.constraint(equalToConstant: 0.0)

        let quadViewConstraints = [
            quadView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            quadView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            quadViewWidthConstraint,
            quadViewHeightConstraint
        ]

        NSLayoutConstraint.activate(quadViewConstraints + imageViewConstraints + overlayConstraints)
    }

    // MARK: - Actions
    @objc func cancelButtonTapped() {
        if let imageScannerController = navigationController as? ImageScannerController {
            imageScannerController.imageScannerDelegate?.imageScannerControllerDidCancel(imageScannerController)
        }
    }

    @objc func pushReviewController() {
        guard let quad = quadView.quad,
            let ciImage = CIImage(image: image) else {
                if let imageScannerController = navigationController as? ImageScannerController {
                    let error = ImageScannerControllerError.ciImageCreation
                    imageScannerController.imageScannerDelegate?.imageScannerController(imageScannerController, didFailWithError: error)
                }
                return
        }
        let cgOrientation = CGImagePropertyOrientation(image.imageOrientation)
        let orientedImage = ciImage.oriented(forExifOrientation: Int32(cgOrientation.rawValue))
        let scaledQuad = quad.scale(quadView.bounds.size, image.size)
        self.quad = scaledQuad

        print("🔷🔷🔷 CROP #2 (EditScanViewController - User Edit/Review)")
        print("🔷 Input image size: \(image.size)")
        print("🔷 Input image orientation: \(image.imageOrientation.rawValue)")
        print("🔷 Oriented image extent: \(orientedImage.extent)")
        print("🔷 QuadView bounds: \(quadView.bounds.size)")
        print("🔷 Quad from quadView: TL=\(quad.topLeft), TR=\(quad.topRight), BR=\(quad.bottomRight), BL=\(quad.bottomLeft)")
        print("🔷 Scaled quad: TL=\(scaledQuad.topLeft), TR=\(scaledQuad.topRight), BR=\(scaledQuad.bottomRight), BL=\(scaledQuad.bottomLeft)")
        
        // Cropped Image
        var cartesianScaledQuad = scaledQuad.toCartesian(withHeight: image.size.height)
        cartesianScaledQuad.reorganize()

        print("🔷 Cartesian quad: TL=\(cartesianScaledQuad.topLeft), TR=\(cartesianScaledQuad.topRight), BR=\(cartesianScaledQuad.bottomRight), BL=\(cartesianScaledQuad.bottomLeft)")
        print("🔷 Perspective params: inputTopLeft=\(cartesianScaledQuad.bottomLeft), inputTopRight=\(cartesianScaledQuad.bottomRight), inputBottomLeft=\(cartesianScaledQuad.topLeft), inputBottomRight=\(cartesianScaledQuad.topRight)")

        let filteredImage = orientedImage.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": CIVector(cgPoint: cartesianScaledQuad.bottomLeft),
            "inputTopRight": CIVector(cgPoint: cartesianScaledQuad.bottomRight),
            "inputBottomLeft": CIVector(cgPoint: cartesianScaledQuad.topLeft),
            "inputBottomRight": CIVector(cgPoint: cartesianScaledQuad.topRight)
        ])

        print("🔷 Filtered image extent: \(filteredImage.extent)")

        let croppedImage = UIImage.from(ciImage: filteredImage)
        print("🔷 Output cropped image size: \(croppedImage.size)")
        print("🔷 CROP #2 COMPLETE")
        print("🔷🔷🔷")
        // Enhanced Image
        let enhancedImage = filteredImage.applyingAdaptiveThreshold()?.withFixedOrientation()
        let enhancedScan = enhancedImage.flatMap { ImageScannerScan(image: $0) }

        let results = ImageScannerResults(
            detectedRectangle: scaledQuad,
            originalScan: ImageScannerScan(image: image),
            croppedScan: ImageScannerScan(image: croppedImage),
            enhancedScan: enhancedScan,
            overlayImage: overlayImage
        )

        guard let imageScannerController = navigationController as? ImageScannerController else { return }
        
        // Check if we're editing from thumbnail summary or adding a new scan
        if let editingIndex = editingIndex {
            // We're editing an existing scan from thumbnail summary
            print("📸📸📸 EditScan: Updating scan \(editingIndex + 1) and returning to thumbnail summary")
            imageScannerController.updateScanResultFromThumbnailSummary(results, at: editingIndex)
            
            // Return to thumbnail summary (pop back to it)
            navigationController?.popViewController(animated: true)
        } else if imageScannerController.isMultiPageScanningEnabled {
            // New scan from live camera - add to results and show thumbnail summary
            print("📸📸📸 EditScan: Adding new scan from live camera, going to thumbnail summary")
            imageScannerController.addScanResult(results)
            imageScannerController.showThumbnailSummary()
        } else {
            // Traditional single-page flow - go to review screen
            print("📸📸📸 EditScan: Single-page mode, going to review screen")
            let reviewViewController = ReviewViewController(results: results)
            navigationController?.pushViewController(reviewViewController, animated: true)
        }
    }

    private func displayQuad() {
        let imageSize = image.size
        let imageFrame = CGRect(
            origin: quadView.frame.origin,
            size: CGSize(width: quadViewWidthConstraint.constant, height: quadViewHeightConstraint.constant)
        )

        print("📸📸📸 EditScan: displayQuad - imageSize: \(imageSize), imageFrame: \(imageFrame.size)")
        print("📸📸📸 EditScan: Original quad - TL(\(quad.topLeft.x), \(quad.topLeft.y)) TR(\(quad.topRight.x), \(quad.topRight.y)) BR(\(quad.bottomRight.x), \(quad.bottomRight.y)) BL(\(quad.bottomLeft.x), \(quad.bottomLeft.y))")

        let scaleTransform = CGAffineTransform.scaleTransform(forSize: imageSize, aspectFillInSize: imageFrame.size)
        let transforms = [scaleTransform]
        let transformedQuad = quad.applyTransforms(transforms)

        print("📸📸📸 EditScan: Transformed quad - TL(\(transformedQuad.topLeft.x), \(transformedQuad.topLeft.y)) TR(\(transformedQuad.topRight.x), \(transformedQuad.topRight.y)) BR(\(transformedQuad.bottomRight.x), \(transformedQuad.bottomRight.y)) BL(\(transformedQuad.bottomLeft.x), \(transformedQuad.bottomLeft.y))")

        quadView.drawQuadrilateral(quad: transformedQuad, animated: false)
    }

    /// The quadView should be lined up on top of the actual image displayed by the imageView.
    /// Since there is no way to know the size of that image before run time, we adjust the constraints
    /// to make sure that the quadView is on top of the displayed image.
    private func adjustQuadViewConstraints() {
        let frame = AVMakeRect(aspectRatio: image.size, insideRect: imageView.bounds)
        quadViewWidthConstraint.constant = frame.size.width
        quadViewHeightConstraint.constant = frame.size.height
    }

    /// Generates a `Quadrilateral` object that's centered and 90% of the size of the passed in image.
    private static func defaultQuad(forImage image: UIImage) -> Quadrilateral {
        let topLeft = CGPoint(x: image.size.width * 0.05, y: image.size.height * 0.05)
        let topRight = CGPoint(x: image.size.width * 0.95, y: image.size.height * 0.05)
        let bottomRight = CGPoint(x: image.size.width * 0.95, y: image.size.height * 0.95)
        let bottomLeft = CGPoint(x: image.size.width * 0.05, y: image.size.height * 0.95)

        let quad = Quadrilateral(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft)

        return quad
    }

}
