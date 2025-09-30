//
//  ThumbnailSummaryViewController.swift
//  WeScan
//
//  Created by Assistant on 2025-09-10.
//  Copyright © 2025 WeTransfer. All rights reserved.
//

import UIKit

/// A view controller that displays thumbnails of captured pages and allows navigation to edit mode
public final class ThumbnailSummaryViewController: UIViewController {
    
    /// Array of captured scan results
    private var scanResults: [ImageScannerResults] = []
    
    /// Currently displayed page for editing (if any)
    private var currentEditingIndex: Int?
    
    /// Delegate for handling completion
    weak var delegate: ImageScannerController?
    
    // MARK: - UI Components
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Scanned Pages"
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .systemBackground
        scrollView.showsVerticalScrollIndicator = true
        return scrollView
    }()
    
    private lazy var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private lazy var saveDoneButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("✓ Finish & Save All Pages", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(saveDoneButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var continueButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("+ Scan More Pages", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.backgroundColor = .systemGreen
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(continueButtonTapped), for: .touchUpInside)
        return button
    }()
    
    // MARK: - Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupConstraints()
        setupNavigationBar()
        updateThumbnails()
        
        print("📸📸📸 ThumbnailSummary: Loaded with \(scanResults.count) scanned pages")
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateThumbnails()
    }
    
    // MARK: - Setup
    
    private func setupViews() {
        view.backgroundColor = .systemBackground
        view.addSubview(titleLabel)
        view.addSubview(scrollView)
        view.addSubview(saveDoneButton)
        view.addSubview(continueButton)
        scrollView.addSubview(stackView)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Title
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: continueButton.topAnchor, constant: -16),
            
            // Stack view
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
            
            // Continue button
            continueButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            continueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            continueButton.bottomAnchor.constraint(equalTo: saveDoneButton.topAnchor, constant: -8),
            continueButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Save & Done button
            saveDoneButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            saveDoneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            saveDoneButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            saveDoneButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    private func setupNavigationBar() {
        title = "Your Scanned Pages"
        
        let cancelButton = UIBarButtonItem(
            title: "Cancel",
            style: .plain,
            target: self,
            action: #selector(cancelButtonTapped)
        )
        navigationItem.leftBarButtonItem = cancelButton
    }
    
    // MARK: - Public Methods
    
    /// Add a new scan result to the summary
    public func addScanResult(_ result: ImageScannerResults) {
        scanResults.append(result)
        updateThumbnails()
        
        print("📸📸📸 ThumbnailSummary: Added page \(scanResults.count), aspect ratio: \(String(format: "%.3f", result.detectedRectangle?.aspectRatio ?? 0.0))")
    }
    
    /// Set all scan results at once
    public func setScanResults(_ results: [ImageScannerResults]) {
        scanResults = results
        updateThumbnails()
        
        print("📸📸📸 ThumbnailSummary: Set \(results.count) pages")
    }
    
    /// Update a specific scan result after editing
    public func updateScanResult(at index: Int, with result: ImageScannerResults) {
        guard index >= 0 && index < scanResults.count else { return }
        scanResults[index] = result
        updateThumbnails()
        
        print("📸📸📸 ThumbnailSummary: Updated page \(index + 1)")
    }
    
    // MARK: - Private Methods
    
    private func updateThumbnails() {
        // Clear existing thumbnails
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        for (index, result) in scanResults.enumerated() {
            let thumbnailView = createThumbnailView(for: result, at: index)
            stackView.addArrangedSubview(thumbnailView)
        }
        
        // Update title
        titleLabel.text = scanResults.count == 1 ? "1 Scanned Page" : "\(scanResults.count) Scanned Pages"
    }
    
    private func createThumbnailView(for result: ImageScannerResults, at index: Int) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .secondarySystemBackground
        containerView.layer.cornerRadius = 12
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: 2)
        containerView.layer.shadowRadius = 8
        containerView.layer.shadowOpacity = 0.1
        
        // Thumbnail image
        let imageView = UIImageView()
        imageView.image = result.croppedScan.image
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        // Page number badge
        let badgeView = UIView()
        badgeView.backgroundColor = .systemBlue
        badgeView.layer.cornerRadius = 12
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        
        let badgeLabel = UILabel()
        badgeLabel.text = "\(index + 1)"
        badgeLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        badgeView.addSubview(badgeLabel)
        
        // Edit button
        let editButton = UIButton(type: .system)
        editButton.setTitle("Edit", for: .normal)
        editButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        editButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        editButton.setTitleColor(.white, for: .normal)
        editButton.layer.cornerRadius = 6
        editButton.translatesAutoresizingMaskIntoConstraints = false
        editButton.tag = index
        editButton.addTarget(self, action: #selector(editButtonTapped(_:)), for: .touchUpInside)
        
        // Delete button
        let deleteButton = UIButton(type: .system)
        deleteButton.setTitle("Delete", for: .normal)
        deleteButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        deleteButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.8)
        deleteButton.setTitleColor(.white, for: .normal)
        deleteButton.layer.cornerRadius = 6
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.tag = index
        deleteButton.addTarget(self, action: #selector(deleteButtonTapped(_:)), for: .touchUpInside)
        
        // Add tap gesture to entire container
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(thumbnailTapped(_:)))
        containerView.addGestureRecognizer(tapGesture)
        containerView.tag = index
        
        // Add subviews
        containerView.addSubview(imageView)
        containerView.addSubview(badgeView)
        containerView.addSubview(editButton)
        containerView.addSubview(deleteButton)
        
        // Constraints
        NSLayoutConstraint.activate([
            containerView.heightAnchor.constraint(equalToConstant: 120),
            
            // Image view
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            imageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 80),
            imageView.heightAnchor.constraint(equalToConstant: 100),
            
            // Badge
            badgeView.topAnchor.constraint(equalTo: imageView.topAnchor, constant: -4),
            badgeView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
            badgeView.widthAnchor.constraint(equalToConstant: 24),
            badgeView.heightAnchor.constraint(equalToConstant: 24),
            
            badgeLabel.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),
            
            // Edit button
            editButton.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 16),
            editButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor, constant: -15),
            editButton.widthAnchor.constraint(equalToConstant: 60),
            editButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Delete button
            deleteButton.leadingAnchor.constraint(equalTo: editButton.trailingAnchor, constant: 8),
            deleteButton.centerYAnchor.constraint(equalTo: editButton.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 60),
            deleteButton.heightAnchor.constraint(equalToConstant: 30)
        ])
        
        return containerView
    }
    
    // MARK: - Actions
    
    @objc private func thumbnailTapped(_ gesture: UITapGestureRecognizer) {
        guard let containerView = gesture.view else { return }
        let index = containerView.tag
        editPage(at: index)
    }
    
    @objc private func editButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        editPage(at: index)
    }
    
    @objc private func deleteButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        deletePage(at: index)
    }
    
    @objc private func saveDoneButtonTapped() {
        guard let delegate = delegate else { return }
        
        print("📸📸📸 ThumbnailSummary: Completing scan with \(scanResults.count) pages")
        
        if delegate.isMultiPageScanningEnabled {
            delegate.multiPageDelegate?.imageScannerController(delegate, didFinishScanningWithMultipleResults: scanResults)
        } else if let firstResult = scanResults.first {
            delegate.imageScannerDelegate?.imageScannerController(delegate, didFinishScanningWithResults: firstResult)
        }
    }
    
    @objc private func continueButtonTapped() {
        print("📸📸📸 ThumbnailSummary: Continuing scan, returning to camera")
        navigationController?.popToViewController(navigationController?.viewControllers.first ?? self, animated: true)
    }
    
    @objc private func cancelButtonTapped() {
        guard let delegate = delegate else { return }
        print("📸📸📸 ThumbnailSummary: Cancelled scanning")
        
        if delegate.isMultiPageScanningEnabled {
            delegate.multiPageDelegate?.imageScannerControllerDidCancel(delegate)
        } else {
            delegate.imageScannerDelegate?.imageScannerControllerDidCancel(delegate)
        }
    }
    
    private func editPage(at index: Int) {
        guard index >= 0 && index < scanResults.count else { return }
        
        let result = scanResults[index]
        currentEditingIndex = index
        
        print("📸📸📸 ThumbnailSummary: Editing page \(index + 1)")
        print("📸📸📸 ThumbnailSummary: Has overlay image: \(result.overlayImage != nil)")
        
        let editVC = EditScanViewController(
            image: result.originalScan.image,
            quad: result.detectedRectangle,
            overlayImage: result.overlayImage,
            rotateImage: false  // Match gallery flow - image has orientation metadata
        )
        editVC.editingIndex = index
        navigationController?.pushViewController(editVC, animated: true)
    }
    
    private func deletePage(at index: Int) {
        guard index >= 0 && index < scanResults.count else { return }
        
        let alert = UIAlertController(
            title: "Delete Page",
            message: "Are you sure you want to delete page \(index + 1)?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            self.scanResults.remove(at: index)
            self.updateThumbnails()
            
            print("📸📸📸 ThumbnailSummary: Deleted page \(index + 1), \(self.scanResults.count) pages remaining")
            
            // If no pages left, go back to scanner
            if self.scanResults.isEmpty {
                self.continueButtonTapped()
            }
        })
        
        present(alert, animated: true)
    }
}
