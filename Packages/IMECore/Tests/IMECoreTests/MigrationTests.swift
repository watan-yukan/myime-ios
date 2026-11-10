import XCTest
@testable import IMECore

/// 使用者資料版本化與 migration（Issue #11，FR-D06）。全部使用虛構資料。
final class MigrationTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("imecore-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var file: URL { directory.appendingPathComponent("settings.json") }

    /// v1 → v2 把 `sound` 改名為 `keySound`；v2 → v3 新增 `haptics`。
    private var migrator: JSONMigrator {
        JSONMigrator(currentVersion: 3, steps: [
            1: { object in
                if let value = object.removeValue(forKey: "sound") { object["keySound"] = value }
            },
            2: { object in object["haptics"] = true },
        ])
    }

    private func write(_ text: String) throws {
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    private func readObject() throws -> JSONObject {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? JSONObject)
    }

    // MARK: - JSONMigrator（記憶體內）

    func testCurrentVersionIsReturnedUnchanged() throws {
        guard case .current(let object) = try migrator.migrate(["schemaVersion": 3, "keySound": true]) else {
            return XCTFail("應為 current")
        }
        XCTAssertEqual(object["keySound"] as? Bool, true)
    }

    func testChainsStepsInOrder() throws {
        guard case .migrated(let object, let from) = try migrator.migrate(["schemaVersion": 1, "sound": false]) else {
            return XCTFail("應為 migrated")
        }
        XCTAssertEqual(from, 1)
        XCTAssertEqual(object["schemaVersion"] as? Int, 3)
        XCTAssertEqual(object["keySound"] as? Bool, false)
        XCTAssertNil(object["sound"])
        XCTAssertEqual(object["haptics"] as? Bool, true)
    }

    func testMigratesFromMiddleVersion() throws {
        guard case .migrated(let object, let from) = try migrator.migrate(["schemaVersion": 2]) else {
            return XCTFail("應為 migrated")
        }
        XCTAssertEqual(from, 2)
        XCTAssertEqual(object["haptics"] as? Bool, true)
    }

    func testNewerVersionIsReadOnly() throws {
        guard case .newer(_, let version) = try migrator.migrate(["schemaVersion": 9]) else {
            return XCTFail("應為 newer")
        }
        XCTAssertEqual(version, 9)
    }

    func testMissingVersionAndMissingStepThrow() {
        XCTAssertThrowsError(try migrator.migrate(["keySound": true])) {
            XCTAssertEqual($0 as? MigrationError, .missingSchemaVersion)
        }
        let gap = JSONMigrator(currentVersion: 3, steps: [1: { _ in }])
        XCTAssertThrowsError(try gap.migrate(["schemaVersion": 1])) {
            XCTAssertEqual($0 as? MigrationError, .missingStep(from: 2))
        }
    }

    // MARK: - VersionedFile

    func testMissingFile() {
        guard case .missing = VersionedFile.load(from: file, migrator: migrator) else {
            return XCTFail("應為 missing")
        }
    }

    func testLoadsCurrentFileWithoutTouchingIt() throws {
        try write(#"{"schemaVersion": 3, "keySound": true, "haptics": false}"#)
        let before = try Data(contentsOf: file)
        guard case .loaded(let object) = VersionedFile.load(from: file, migrator: migrator) else {
            return XCTFail("應為 loaded")
        }
        XCTAssertEqual(object["haptics"] as? Bool, false)
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    func testMigratesFileWritesBackAndKeepsBackup() throws {
        try write(#"{"schemaVersion": 1, "sound": false}"#)
        let original = try Data(contentsOf: file)

        guard case .migrated(let object, let backup) = VersionedFile.load(from: file, migrator: migrator) else {
            return XCTFail("應為 migrated")
        }
        XCTAssertEqual(object["schemaVersion"] as? Int, 3)

        let onDisk = try readObject()
        XCTAssertEqual(onDisk["schemaVersion"] as? Int, 3)
        XCTAssertEqual(onDisk["keySound"] as? Bool, false)

        XCTAssertEqual(backup.lastPathComponent, "settings.json.v1.bak")
        XCTAssertEqual(try Data(contentsOf: backup), original, "備份是升級前的原始內容")
    }

    func testSecondLoadAfterMigrationIsCurrent() throws {
        try write(#"{"schemaVersion": 1}"#)
        _ = VersionedFile.load(from: file, migrator: migrator)
        guard case .loaded = VersionedFile.load(from: file, migrator: migrator) else {
            return XCTFail("升級後再讀應為 loaded")
        }
    }

    func testNewerFileIsNeverWritten() throws {
        try write(#"{"schemaVersion": 7, "future": 1}"#)
        let before = try Data(contentsOf: file)
        guard case .readOnlyNewer(let object, let version) = VersionedFile.load(from: file, migrator: migrator) else {
            return XCTFail("應為 readOnlyNewer")
        }
        XCTAssertEqual(version, 7)
        XCTAssertEqual(object["future"] as? Int, 1)
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    func testFailedMigrationLeavesOriginalUntouched() throws {
        struct Boom: Error {}
        let failing = JSONMigrator(currentVersion: 2, steps: [1: { _ in throw Boom() }])
        try write(#"{"schemaVersion": 1, "keep": "me"}"#)
        let before = try Data(contentsOf: file)

        guard case .migrationFailed = VersionedFile.load(from: file, migrator: failing) else {
            return XCTFail("應為 migrationFailed")
        }
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["settings.json"],
                       "失敗時不留下備份或暫存檔")
    }

    func testFileWithoutVersionFailsWithoutChange() throws {
        try write(#"{"keySound": true}"#)
        let before = try Data(contentsOf: file)
        guard case .migrationFailed(let error) = VersionedFile.load(from: file, migrator: migrator) else {
            return XCTFail("應為 migrationFailed")
        }
        XCTAssertEqual(error as? MigrationError, .missingSchemaVersion)
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    func testCorruptFileIsMovedAside() throws {
        try write("{ not json")
        guard case .corrupt(let moved) = VersionedFile.load(from: file, migrator: migrator) else {
            return XCTFail("應為 corrupt")
        }
        XCTAssertEqual(moved?.lastPathComponent, "settings.json.corrupt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try String(contentsOf: try XCTUnwrap(moved), encoding: .utf8), "{ not json")
    }

    func testSecondCorruptFileDoesNotOverwriteFirst() throws {
        try write("first")
        _ = VersionedFile.load(from: file, migrator: migrator)
        try write("second")
        guard case .corrupt(let moved) = VersionedFile.load(from: file, migrator: migrator) else {
            return XCTFail("應為 corrupt")
        }
        XCTAssertEqual(moved?.lastPathComponent, "settings.json.corrupt2")
        let first = directory.appendingPathComponent("settings.json.corrupt")
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "first")
    }

    func testTopLevelArrayCountsAsCorrupt() throws {
        try write("[1, 2, 3]")
        guard case .corrupt = VersionedFile.load(from: file, migrator: migrator) else {
            return XCTFail("最外層不是物件應視為 corrupt")
        }
    }

    func testSaveAndReloadRoundTrip() throws {
        try VersionedFile.save(["schemaVersion": 3, "name": "測試", "items": [1, 2, 3]], to: file)
        guard case .loaded(let object) = VersionedFile.load(from: file, migrator: migrator) else {
            return XCTFail("應為 loaded")
        }
        XCTAssertEqual(object["name"] as? String, "測試")
        XCTAssertEqual(object["items"] as? [Int], [1, 2, 3])
    }
}
