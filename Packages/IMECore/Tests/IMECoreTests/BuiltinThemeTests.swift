import XCTest
@testable import IMECore

final class BuiltinThemeTests: XCTestCase {
    /// 內建後備的「原生」主題必須與 Shared/Themes/native.json 完全一致。
    func testEmbeddedNativeThemeMatchesFile() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let fileTheme = try Theme.load(from: Data(contentsOf: url.appendingPathComponent("Shared/Themes/native.json")))
        XCTAssertEqual(BuiltinThemes.native(), fileTheme)
    }
}
