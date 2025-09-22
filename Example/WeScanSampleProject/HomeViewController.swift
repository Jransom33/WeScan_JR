//
//  ViewController.swift
//  WeScanSampleProject
//
//  Created by Boris Emorine on 2/8/18.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import UIKit
import WeScan

final class HomeViewController: UIViewController {

    private lazy var logoImageView: UIImageView = {
        let image = #imageLiteral(resourceName: "WeScanLogo")
        let imageView = UIImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var logoLabel: UILabel = {
        let label = UILabel()
        label.text = "WeScan"
        label.font = UIFont.systemFont(ofSize: 25.0, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var scanButton: UIButton = {
        let button = UIButton(type: .custom)
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        button.setTitle("Scan Item", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(scanOrSelectImage(_:)), for: .touchUpInside)
        button.backgroundColor = UIColor(red: 64.0 / 255.0, green: 159 / 255.0, blue: 255 / 255.0, alpha: 1.0)
        button.layer.cornerRadius = 10.0
        return button
    }()

    // MARK: - Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupViews()
        setupConstraints()
    }

    // MARK: - Setups

    private func setupViews() {
        view.addSubview(logoImageView)
        view.addSubview(logoLabel)
        view.addSubview(scanButton)
    }

    private func setupConstraints() {

        let logoImageViewConstraints = [
            logoImageView.widthAnchor.constraint(equalToConstant: 150.0),
            logoImageView.heightAnchor.constraint(equalToConstant: 150.0),
            logoImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            NSLayoutConstraint(
                item: logoImageView,
                attribute: .centerY,
                relatedBy: .equal,
                toItem: view,
                attribute: .centerY,
                multiplier: 0.75,
                constant: 0.0
            )
        ]

        let logoLabelConstraints = [
            logoLabel.topAnchor.constraint(equalTo: logoImageView.bottomAnchor, constant: 20.0),
            logoLabel.centerXAnchor.constraint(equalTo: logoImageView.centerXAnchor)
        ]

        NSLayoutConstraint.activate(logoLabelConstraints + logoImageViewConstraints)

        if #available(iOS 11.0, *) {
            let scanButtonConstraints = [
                scanButton.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 16),
                scanButton.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor, constant: -16),
                scanButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
                scanButton.heightAnchor.constraint(equalToConstant: 55)
            ]

            NSLayoutConstraint.activate(scanButtonConstraints)
        } else {
            let scanButtonConstraints = [
                scanButton.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 16),
                scanButton.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -16),
                scanButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
                scanButton.heightAnchor.constraint(equalToConstant: 55)
            ]

            NSLayoutConstraint.activate(scanButtonConstraints)
        }
    }

    // MARK: - Actions

    @objc func scanOrSelectImage(_ sender: UIButton) {
        let actionSheet = UIAlertController(
            title: "Would you like to scan an image or select one from your photo library?",
            message: nil,
            preferredStyle: .actionSheet
        )

        let newAction = UIAlertAction(title: "A new scan", style: .default) { _ in
            guard let controller = self.storyboard?.instantiateViewController(withIdentifier: "NewCameraViewController") else { return }
            controller.modalPresentationStyle = .fullScreen
            self.present(controller, animated: true, completion: nil)
        }

        let scanAction = UIAlertAction(title: "Scan Single Page", style: .default) { _ in
            self.scanImage()
        }
        
        let multiPageScanAction = UIAlertAction(title: "Scan Multiple Pages", style: .default) { _ in
            self.scanMultipleImages()
        }

        let selectAction = UIAlertAction(title: "Select", style: .default) { _ in
            self.selectImage()
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)

        actionSheet.addAction(scanAction)
        actionSheet.addAction(multiPageScanAction)
        actionSheet.addAction(selectAction)
        actionSheet.addAction(cancelAction)
        actionSheet.addAction(newAction)

        present(actionSheet, animated: true)
    }

    func scanImage() {
        // MARK: - New CoreML Usage Pattern with Confidence Configuration (iOS 11.0+)
        /*
        // Option 1: Configure with default confidence settings
        do {
            try ImageScannerController.configure(modelName: "CornerKeypoints_model_epoch_30_simple")
            // Now the scanner will use your custom CoreML model for corner detection
        } catch {
            print("Failed to configure WeScan with CoreML model: \(error)")
            // Will use default rectangle detection
        }

        // Option 2: Configure with custom confidence settings
        do {
            let config = CoreMLDetectionConfig(
                minConfidence: -1.5,      // Stricter confidence threshold (default: -2.0)
                minCornerDistance: 10.0,  // Minimum distance between corners (default: 5.0)
                applySigmoid: true        // Convert logits to probabilities (default: false)
            )
            try ImageScannerController.configure(modelName: "CornerKeypoints_model_epoch_30_simple", config: config)
        } catch {
            print("Failed to configure WeScan with CoreML model: \(error)")
        }

        // Option 3: Configure with MLModel directly and custom config
        /*
        do {
            guard let modelURL = Bundle.main.url(forResource: "YourModel", withExtension: "mlpackage") else {
                print("CoreML model not found")
                return
            }
            let model = try MLModel(contentsOf: modelURL)
            
            let config = CoreMLDetectionConfig(
                minConfidence: -1.0,      // Very strict confidence
                minCornerDistance: 15.0,  // Ensure corners are well separated
                applySigmoid: false       // Keep raw logits for debugging
            )
            try ImageScannerController.configure(with: model, config: config)
        } catch {
            print("Failed to configure WeScan: \(error)")
        }
        */
        */
        
        let scannerViewController = ImageScannerController(delegate: self)
        scannerViewController.modalPresentationStyle = .fullScreen

        if #available(iOS 13.0, *) {
            scannerViewController.navigationBar.tintColor = .label
        } else {
            scannerViewController.navigationBar.tintColor = .black
        }

        present(scannerViewController, animated: true)
    }
    
    func scanMultipleImages() {
        let scannerViewController = ImageScannerController(multiPageDelegate: self)
        scannerViewController.modalPresentationStyle = .fullScreen

        if #available(iOS 13.0, *) {
            scannerViewController.navigationBar.tintColor = .label
        } else {
            scannerViewController.navigationBar.tintColor = .black
        }

        present(scannerViewController, animated: true)
    }

    func selectImage() {
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.sourceType = .photoLibrary
        present(imagePicker, animated: true)
    }

}

extension HomeViewController: ImageScannerControllerDelegate {
    func imageScannerController(_ scanner: ImageScannerController, didFailWithError error: Error) {
        assertionFailure("Error occurred: \(error)")
    }

    func imageScannerController(_ scanner: ImageScannerController, didFinishScanningWithResults results: ImageScannerResults) {
        scanner.dismiss(animated: true, completion: nil)
    }

    func imageScannerControllerDidCancel(_ scanner: ImageScannerController) {
        scanner.dismiss(animated: true, completion: nil)
    }

}

extension HomeViewController: MultiPageImageScannerControllerDelegate {
    func imageScannerController(_ scanner: ImageScannerController, didFinishScanningWithMultipleResults results: [ImageScannerResults]) {
        print("📸📸📸 Example: Completed multi-page scan with \\(results.count) pages")
        
        // Create alert to show results
        let alert = UIAlertController(
            title: "Multi-Page Scan Complete", 
            message: "Successfully scanned \\(results.count) pages!\\n\\nIn a real app, you would save these images or process them further.", 
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        scanner.dismiss(animated: true) { [weak self] in
            self?.present(alert, animated: true)
        }
    }
}

extension HomeViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)

        guard let image = info[.originalImage] as? UIImage else { return }
        let scannerViewController = ImageScannerController(image: image, delegate: self)
        present(scannerViewController, animated: true)
    }
}
