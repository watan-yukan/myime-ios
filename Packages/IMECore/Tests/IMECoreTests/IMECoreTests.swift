import XCTest
@testable import IMECore

final class IMECoreTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertFalse(IMECore.version.isEmpty)
        XCTAssertEqual(IMECore.tableFormatVersion, 1)
    }

    func testInputTypesAreComparable() {
        XCTAssertEqual(InputEvent.key("a"), InputEvent.key("a"))
        XCTAssertNotEqual(InputEvent.key("a"), InputEvent.shiftedKey("a"))
        XCTAssertEqual(OutputAction.insert("一"), OutputAction.insert("一"))
    }

    /// 確認虛構測試碼表有被打包進測試資源，後續 #2 解析器測試會用到。
    func testSampleFixtureIsBundled() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "sample", withExtension: "cin", subdirectory: "Fixtures")
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("%chardef begin"))
        XCTAssertTrue(text.contains("%ename SampleTable"))
    }
}
