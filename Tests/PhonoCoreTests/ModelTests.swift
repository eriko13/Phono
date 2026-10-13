import Foundation
import XCTest
@testable import PhonoCore

final class ModelTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/test")

    func testDirectory() {
        XCTAssertEqual(
            Model.directory(home: home).path,
            "/Users/test/Library/Application Support/Phono/Phonon-2-CoreML")
    }

    func testInstalledOnlyWhenEveryFileExists() {
        let directory = Model.directory(home: home)
        XCTAssertTrue(Model.isInstalled(at: directory) { _ in true })
        XCTAssertFalse(Model.isInstalled(at: directory) { _ in false })
        XCTAssertFalse(Model.isInstalled(at: directory) { !$0.hasSuffix("weight.bin") })
    }

    func testDuration() {
        XCTAssertEqual(Model.duration(sampleCount: 24_000), 1.5)
    }
}
