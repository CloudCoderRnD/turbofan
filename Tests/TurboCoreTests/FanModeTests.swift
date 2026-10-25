// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import XCTest
@testable import TurboCore

final class FanModeTests: XCTestCase {
    func testManualModesHaveNoFraction() {
        XCTAssertNil(FanMode.auto.fraction(at: 70))
        XCTAssertNil(FanMode.constant(rpm: 3000).fraction(at: 70))
    }

    func testLinearSensorMode() throws {
        let mode = FanMode.sensor(key: "TCXC", from: 50, to: 80)
        XCTAssertEqual(try XCTUnwrap(mode.fraction(at: 65)), 0.5, accuracy: 1e-9)
        XCTAssertEqual(mode.fraction(at: 20), 0)
        XCTAssertEqual(mode.fraction(at: 120), 1)
        XCTAssertEqual(mode.sensorKey, "TCXC")
    }

    func testLinearModeWithEmptyRangeRunsFull() {
        XCTAssertEqual(FanMode.sensor(key: "TCXC", from: 70, to: 70).fraction(at: 10), 1)
        XCTAssertEqual(FanMode.sensor(key: "TCXC", from: 80, to: 60).fraction(at: 10), 1)
    }

    func testCurveInterpolation() {
        let points = [CurvePoint(temp: 40, percent: 0), CurvePoint(temp: 60, percent: 50), CurvePoint(temp: 80, percent: 100)]
        XCTAssertEqual(CurvePoint.interpolate(points, at: 30), 0)
        XCTAssertEqual(CurvePoint.interpolate(points, at: 50), 25, accuracy: 1e-9)
        XCTAssertEqual(CurvePoint.interpolate(points, at: 70), 75, accuracy: 1e-9)
        XCTAssertEqual(CurvePoint.interpolate(points, at: 95), 100)
        // Order of points must not matter.
        XCTAssertEqual(CurvePoint.interpolate(points.reversed(), at: 50), 25, accuracy: 1e-9)
        XCTAssertEqual(FanMode.curve(key: "TCXC", points: points).fraction(at: 70) ?? -1, 0.75, accuracy: 1e-9)
    }

    func testEmptyCurveRunsFull() {
        XCTAssertEqual(CurvePoint.interpolate([], at: 40), 100)
    }

    /// Every curve preset must reach full speed by 100 °C and never slow down as it gets hotter.
    func testCurvePresetsAreSafe() {
        for preset in FanPreset.allCases {
            guard case let .curve(key, points) = preset.mode else { continue }
            XCTAssertEqual(key, FanPreset.sensor, "\(preset)")
            XCTAssertEqual(CurvePoint.interpolate(points, at: 100), 100, "\(preset) not at full speed at 100 °C")
            var last = -1.0
            for t in stride(from: 20.0, through: 110.0, by: 1.0) {
                let p = CurvePoint.interpolate(points, at: t)
                XCTAssertGreaterThanOrEqual(p, last, "\(preset) slows down at \(t) °C")
                XCTAssert((0...100).contains(p), "\(preset) out of range at \(t) °C")
                last = p
            }
        }
    }

    func testPresetMatching() {
        for preset in FanPreset.allCases {
            XCTAssertEqual(FanPreset.matching(preset.mode), preset)
        }
        XCTAssertNil(FanPreset.matching(.constant(rpm: 2500)))
    }

    /// Modes travel over the daemon socket and are saved to fans.json, so they must survive JSON.
    func testModesRoundTripThroughJSON() throws {
        let modes = FanPreset.allCases.map(\.mode) + [.sensor(key: "TG0P", from: 45, to: 90)]
        for mode in modes {
            let data = try JSONEncoder().encode(mode)
            XCTAssertEqual(try JSONDecoder().decode(FanMode.self, from: data), mode)
        }
    }

    func testSensorNames() {
        XCTAssertEqual(SMC.sensorName("TCXC"), "CPU (PECI)")
        XCTAssertEqual(SMC.sensorName("TC3C"), "CPU core 3")
        XCTAssertEqual(SMC.sensorName("TZZZ"), "TZZZ")
    }
}
