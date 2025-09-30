//
//  MotionStabilityMonitor.swift
//  WeScan
//
//  Created by AI Assistant.
//

import CoreMotion
import Foundation

/// Monitors device motion to determine when the device is stable enough to run heavy AI.
/// Uses simple thresholds with hysteresis on linear acceleration and rotation rate.
final class MotionStabilityMonitor {

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()

    /// Update interval for motion samples
    private let updateInterval: TimeInterval

    /// Low-pass filtered magnitudes
    private var filteredAccel: Double = 0
    private var filteredGyro: Double = 0

    /// Exponential smoothing factor (0..1)
    private let smoothingAlpha: Double = 0.2

    /// Thresholds to determine stability (very lenient for real-world handheld use)
    private let accelStableThreshold: Double = 0.08   // in g (~m/s^2 normalized) - relaxed
    private let gyroStableThreshold: Double = 0.10    // rad/s - relaxed

    /// Hysteresis margins (much wider to prevent losing stability easily)
    private let accelUnstableThreshold: Double = 0.20  // Need significant movement to lose stability
    private let gyroUnstableThreshold: Double = 0.25

    /// Require consecutive stable samples before reporting stable
    private let requiredStableSamples: Int = 5   // ~83ms at 60Hz - faster to establish
    private let requiredUnstableSamples: Int = 10 // Much harder to lose stability once achieved

    private var stableSampleCount: Int = 0
    private var unstableSampleCount: Int = 0

    private(set) var isStable: Bool = false

    init(updateInterval: TimeInterval = 1.0 / 60.0) {
        self.updateInterval = updateInterval
    }

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }

            // Use userAcceleration (gravity removed) magnitude
            let a = motion.userAcceleration
            let accelMag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)

            // Use rotationRate magnitude
            let r = motion.rotationRate
            let gyroMag = sqrt(r.x * r.x + r.y * r.y + r.z * r.z)

            // Low-pass filter
            self.filteredAccel = self.smoothingAlpha * accelMag + (1 - self.smoothingAlpha) * self.filteredAccel
            self.filteredGyro = self.smoothingAlpha * gyroMag + (1 - self.smoothingAlpha) * self.filteredGyro

            // Hysteresis-based stability detection
            let accelIsStable = self.filteredAccel < self.accelStableThreshold
            let gyroIsStable = self.filteredGyro < self.gyroStableThreshold
            let accelIsUnstable = self.filteredAccel > self.accelUnstableThreshold
            let gyroIsUnstable = self.filteredGyro > self.gyroUnstableThreshold

            if accelIsStable && gyroIsStable {
                self.stableSampleCount += 1
                self.unstableSampleCount = 0
                if !self.isStable && self.stableSampleCount >= self.requiredStableSamples {
                    print("📱 Motion: STABLE (accel: \(String(format: "%.3f", self.filteredAccel)), gyro: \(String(format: "%.3f", self.filteredGyro)))")
                    self.isStable = true
                }
            } else if accelIsUnstable || gyroIsUnstable {
                self.unstableSampleCount += 1
                self.stableSampleCount = 0
                if self.isStable && self.unstableSampleCount >= self.requiredUnstableSamples {
                    print("📱 Motion: UNSTABLE (accel: \(String(format: "%.3f", self.filteredAccel)), gyro: \(String(format: "%.3f", self.filteredGyro)))")
                    self.isStable = false
                }
            } else {
                // In between thresholds, do not change counters drastically
                self.stableSampleCount = max(0, self.stableSampleCount - 1)
                self.unstableSampleCount = max(0, self.unstableSampleCount - 1)
            }
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        isStable = false
        stableSampleCount = 0
        unstableSampleCount = 0
        filteredAccel = 0
        filteredGyro = 0
    }
}


