//
//  KalmanRectangleTracker.swift
//  WeScan
//
//  Created by AI Assistant.
//

import CoreGraphics
import Foundation

/// A lightweight per-corner constant-velocity Kalman filter to predict and smooth rectangle corners.
final class KalmanRectangleTracker {

    private final class CornerFilter {
        // State: [x, y, vx, vy]
        private var x: [Double] = [0, 0, 0, 0]
        private var P: [[Double]] = Array(repeating: Array(repeating: 0, count: 4), count: 4)
        private let Q: [[Double]] // process noise
        private let R: [[Double]] // measurement noise

        init(initial: CGPoint, processNoise: Double = 1e-2, measurementNoise: Double = 3e-1) {
            x[0] = Double(initial.x)
            x[1] = Double(initial.y)
            x[2] = 0
            x[3] = 0
            // Initialize covariance with moderate uncertainty
            P = [[1,0,0,0],[0,1,0,0],[0,0,10,0],[0,0,0,10]]
            Q = [[processNoise,0,0,0],[0,processNoise,0,0],[0,0,processNoise,0],[0,0,0,processNoise]]
            R = [[measurementNoise,0],[0,measurementNoise]]
        }

        func predict(dt: Double) -> CGPoint {
            // State transition F
            // x' = x + vx*dt; y' = y + vy*dt
            let F: [[Double]] = [[1,0,dt,0], [0,1,0,dt], [0,0,1,0], [0,0,0,1]]
            x = matVec(F, x)
            // P = F P F^T + Q
            P = matAdd(matMul(matMul(F, P), transpose(F)), Q)
            return CGPoint(x: x[0], y: x[1])
        }

        func update(measurement: CGPoint) -> CGPoint {
            // Measurement matrix H maps state to [x, y]
            let H: [[Double]] = [[1,0,0,0],[0,1,0,0]]
            let z: [Double] = [Double(measurement.x), Double(measurement.y)]
            // y = z - Hx
            let y = vecSub(z, matVec(H, x))
            // S = H P H^T + R
            let S = matAdd(matMul(matMul(H, P), transpose(H)), R)
            // K = P H^T S^-1
            let K = matMul(matMul(P, transpose(H)), inv2x2(S))
            // x = x + K y
            x = vecAdd(x, matVec(K, y))
            // P = (I - K H) P
            let I = identity(4)
            P = matMul(matSub(I, matMul(K, H)), P)
            return CGPoint(x: x[0], y: x[1])
        }
    }

    private var filters: [CornerFilter]? = nil
    private var lastTimestamp: CFTimeInterval? = nil

    func reset() {
        filters = nil
        lastTimestamp = nil
    }

    /// Initialize or update with a measured quadrilateral at a given timestamp.
    /// - Returns: Smoothed quadrilateral.
    func update(measured quad: Quadrilateral, timestamp: CFTimeInterval) -> Quadrilateral {
        if filters == nil {
            filters = [
                CornerFilter(initial: quad.topLeft),
                CornerFilter(initial: quad.topRight),
                CornerFilter(initial: quad.bottomRight),
                CornerFilter(initial: quad.bottomLeft)
            ]
        }
        let dt = lastTimestamp.flatMap { max(1e-3, timestamp - $0) } ?? 1.0/30.0
        lastTimestamp = timestamp
        guard let filters else { return quad }
        let tl = filters[0].predict(dt: dt); let tlU = filters[0].update(measurement: quad.topLeft)
        let tr = filters[1].predict(dt: dt); let trU = filters[1].update(measurement: quad.topRight)
        let br = filters[2].predict(dt: dt); let brU = filters[2].update(measurement: quad.bottomRight)
        let bl = filters[3].predict(dt: dt); let blU = filters[3].update(measurement: quad.bottomLeft)
        return Quadrilateral(topLeft: tlU, topRight: trU, bottomRight: brU, bottomLeft: blU)
    }

    /// Predict next rectangle when no measurement is available (e.g., during motion)
    func predict(timestamp: CFTimeInterval) -> Quadrilateral? {
        guard let filters, let last = lastTimestamp else { return nil }
        let dt = max(1e-3, timestamp - last)
        let tl = filters[0].predict(dt: dt)
        let tr = filters[1].predict(dt: dt)
        let br = filters[2].predict(dt: dt)
        let bl = filters[3].predict(dt: dt)
        lastTimestamp = timestamp
        return Quadrilateral(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl)
    }
}

// MARK: - Small matrix helpers (2x2/4x4 minimal)

private func matVec(_ A: [[Double]], _ x: [Double]) -> [Double] {
    return A.map { row in zip(row, x).map(*).reduce(0, +) }
}

private func matMul(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
    let rows = A.count, cols = B[0].count, inner = B.count
    var C = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)
    for i in 0..<rows {
        for k in 0..<inner {
            let a = A[i][k]
            if a == 0 { continue }
            for j in 0..<cols { C[i][j] += a * B[k][j] }
        }
    }
    return C
}

private func transpose(_ A: [[Double]]) -> [[Double]] {
    let rows = A.count, cols = A[0].count
    var T = Array(repeating: Array(repeating: 0.0, count: rows), count: cols)
    for i in 0..<rows { for j in 0..<cols { T[j][i] = A[i][j] } }
    return T
}

private func vecAdd(_ a: [Double], _ b: [Double]) -> [Double] { zip(a,b).map(+) }
private func vecSub(_ a: [Double], _ b: [Double]) -> [Double] { zip(a,b).map(-) }
private func matAdd(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] { zip(A,B).map { zip($0,$1).map(+) } }
private func matSub(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] { zip(A,B).map { zip($0,$1).map(-) } }
private func identity(_ n: Int) -> [[Double]] { (0..<n).map { i in (0..<n).map { j in i==j ? 1.0 : 0.0 } } }

private func inv2x2(_ A: [[Double]]) -> [[Double]] {
    let a = A[0][0], b = A[0][1], c = A[1][0], d = A[1][1]
    let det = a*d - b*c
    let invDet = det != 0 ? 1.0/det : 0.0
    return [[ d*invDet, -b*invDet], [-c*invDet, a*invDet]]
}


