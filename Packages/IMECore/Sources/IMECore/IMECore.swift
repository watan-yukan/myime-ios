import Foundation

/// IMECore 的版本資訊。
///
/// 子模組（見 docs/03_架構設計.md 3.1）會依 Issue 逐步加入：
/// `Cin`（#2）、`Table`（#3）、`Composer`（#4）、`Candidates`（#5）……
public enum IMECore {
    /// 引擎版本，隨 App 的 MARKETING_VERSION 調整。
    public static let version = "0.1.0"

    /// 碼表索引檔 `table.idx` 的格式版本（docs/06_資料格式.md 第 2 章）。
    public static let tableFormatVersion: UInt16 = 1
}
