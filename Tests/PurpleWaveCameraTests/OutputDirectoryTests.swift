//
//  OutputDirectoryTests.swift
//  PurpleWaveCameraTests
//

import XCTest
@testable import PurpleWaveCameraCore

final class OutputDirectoryTests: XCTestCase {

    func testNilRequestReturnsExistingTempSubfolder() {
        let dir = OutputDirectory.resolve(nil)
        XCTAssertTrue(dir.lastPathComponent == "PurpleWaveCamera")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    func testRequestedDirectoryIsCreatedAndReturned() throws {
        let requested = FileManager.default.temporaryDirectory
            .appendingPathComponent("ft-output-test-\(UUID().uuidString)", isDirectory: true)

        // Precondition: it doesn't exist yet.
        XCTAssertFalse(FileManager.default.fileExists(atPath: requested.path))

        let resolved = OutputDirectory.resolve(requested)

        XCTAssertEqual(resolved, requested)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved.path))

        // Cleanup.
        try? FileManager.default.removeItem(at: requested)
    }
}
