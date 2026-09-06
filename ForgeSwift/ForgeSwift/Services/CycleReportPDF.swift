import Foundation
#if canImport(UIKit)
import UIKit
#endif
import ForgeCore

/// On-device Apple Cycle PDF. Default share is the system sheet (Mail, Files,
/// MyChart) — zero S3. A temporary private link is optional and expires.
enum CycleReportPDF {
    static func fileName(windowMonths: Int, dayKey: String) -> String {
        "forge-cycle-report-\(windowMonths)m-\(dayKey).pdf"
    }

    static func writeTemporaryPDF(
        windowMonths: Int,
        dayKey: String,
        title: String,
        body: String
    ) throws -> URL {
        let name = fileName(windowMonths: windowMonths, dayKey: dayKey)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let data = render(title: title, body: body)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func render(title: String, body: String) -> Data {
        #if canImport(UIKit)
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let inset: CGFloat = 48
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            var cursor: CGFloat = inset
            func newPage() {
                ctx.beginPage()
                cursor = inset
            }
            newPage()

            let titleFont = UIFont.systemFont(ofSize: 16, weight: .semibold)
            let bodyFont = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.black,
            ]
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: UIColor.darkGray,
            ]
            let width = pageRect.width - inset * 2

            func draw(_ text: String, attrs: [NSAttributedString.Key: Any], spacing: CGFloat) {
                let ns = text as NSString
                let bound = ns.boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs,
                    context: nil
                )
                if cursor + bound.height > pageRect.height - inset {
                    newPage()
                }
                ns.draw(
                    with: CGRect(x: inset, y: cursor, width: width, height: bound.height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs,
                    context: nil
                )
                cursor += bound.height + spacing
            }

            draw(title, attrs: titleAttrs, spacing: 16)
            draw(body, attrs: bodyAttrs, spacing: 0)
        }
        #else
        // macOS unit tests / Linux: a tiny valid PDF so file-write tests still run.
        let escaped = body
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
        let stream = "(Forge Cycle Report \\( \(title) \\) \(escaped.prefix(800))) Tj"
        return Data("%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%% \(stream)\n".utf8)
        #endif
    }
}
