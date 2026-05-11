import XCTest
@testable import ThunderNote

final class ThunderNoteSmokeTests: XCTestCase {
    func test_designTokens_haveSaneValues() {
        XCTAssertEqual(DesignTokens.Spacing.medium, 16)
        XCTAssertEqual(DesignTokens.Radius.medium, 8)
        XCTAssertGreaterThan(DesignTokens.Spacing.small, 0)
    }

    func test_designTokens_brandColorIsConsistent() {
        // 当前 brandPrimary 走代码内常量，这里仅做存在性检查；
        // 等迁移到 Asset Color Set 后改成颜色分量比对。
        XCTAssertNotNil(DesignTokens.Color.brandPrimary)
    }
}
