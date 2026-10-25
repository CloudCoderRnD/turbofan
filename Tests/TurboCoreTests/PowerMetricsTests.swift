// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import XCTest
@testable import TurboCore

final class PowerMetricsTests: XCTestCase {
    /// Trimmed from `powermetrics --samplers cpu_power` on an Intel Mac.
    let sample = """
     (Sat Oct 25 01:00:00 2026 +0200) (2003.12ms elapsed) ***

    **** Processor usage ****

    Intel energy model derived package power (CPUs+GT+SA): 5.66W

    LLC flushed residency: 82.1%

    System Average frequency as fraction of nominal: 72.10% (1730.31 Mhz)
    Package 0 C-state residency: 85.30% (C2: 6.12% C3: 2.01% C6: 0.00% C7: 77.17% )
    """

    func testParsesFullSample() throws {
        let date = Date(timeIntervalSince1970: 0)
        let m = PowerMetrics.parse(sample, date: date)
        XCTAssertEqual(try XCTUnwrap(m.cpuMHz), 1730.31, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m.nominalPercent), 72.10, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m.packageWatts), 5.66, accuracy: 1e-9)
        XCTAssertEqual(m.date, date)
    }

    func testMissingFieldsStayNil() {
        let m = PowerMetrics.parse("**** Processor usage ****\n")
        XCTAssertNil(m.cpuMHz)
        XCTAssertNil(m.nominalPercent)
        XCTAssertNil(m.packageWatts)
    }

    func testWholeNumbersAndCase() {
        let m = PowerMetrics.parse("package power: 12W\nsystem average frequency as fraction of nominal: 100% (2600 MHz)")
        XCTAssertEqual(m.packageWatts, 12)
        XCTAssertEqual(m.nominalPercent, 100)
        XCTAssertEqual(m.cpuMHz, 2600)
    }
}
