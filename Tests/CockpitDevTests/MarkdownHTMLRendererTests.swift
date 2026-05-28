import XCTest
@testable import CockpitDev

final class MarkdownHTMLRendererTests: CockpitDevTestCase {
    func testRendersPipeTableAsSemanticTable() {
        let html = MarkdownHTMLRenderer().renderBody("""
        | Day | Date | Work |
        | --- | --- | --- |
        | 1 | Wed 29 Apr | Parser scaffolding |
        | 2 | Thu 30 Apr | Unit tests |
        """)

        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th>Day</th>"))
        XCTAssertTrue(html.contains("<td>Parser scaffolding</td>"))
    }

    func testRendersLanguageCodeBlockWithSyntaxClass() {
        let html = MarkdownHTMLRenderer().renderBody("""
        ```swift
        let value = "hello"
        ```
        """)

        XCTAssertTrue(html.contains("<pre data-language=\"swift\"><code class=\"language-swift\">"))
        XCTAssertTrue(html.contains("let value = &quot;hello&quot;"))
    }

    func testRendersImages() {
        let html = MarkdownHTMLRenderer().renderBody("![Architecture](https://example.com/diagram.png)")

        XCTAssertTrue(html.contains("<img src=\"https://example.com/diagram.png\" alt=\"Architecture\""))
        XCTAssertTrue(html.contains("<figcaption>Architecture</figcaption>"))
    }

    func testRendersMermaidFenceAsDiagramContainer() {
        let html = MarkdownHTMLRenderer().renderBody("""
        ```mermaid
        graph TD
          A --> B
        ```
        """)

        XCTAssertTrue(html.contains("<div class=\"mermaid\">"))
        XCTAssertTrue(html.contains("graph TD"))
        XCTAssertFalse(html.contains("<pre"))
    }
}
