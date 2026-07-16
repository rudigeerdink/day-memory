//
//  YearPresencePDFRenderer.swift
//  Day Memory
//

import Foundation
import UIKit

enum YearPresencePDFRenderer {
    private static let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4 @ 72 dpi
    private static let margin: CGFloat = 44
    private static let footerHeight: CGFloat = 28

    private static let titleFont = UIFont.systemFont(ofSize: 20, weight: .bold)
    private static let headingFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
    private static let bodyFont = UIFont.systemFont(ofSize: 9.5, weight: .regular)
    private static let bodyBoldFont = UIFont.systemFont(ofSize: 9.5, weight: .semibold)
    private static let captionFont = UIFont.systemFont(ofSize: 8.5, weight: .regular)
    private static let headerFont = UIFont.systemFont(ofSize: 8.5, weight: .semibold)

    private struct Column {
        let title: String
        let width: CGFloat
    }

    private static let columns: [Column] = [
        Column(title: "Date", width: 58),
        Column(title: "Location", width: 168),
        Column(title: "Working", width: 78),
        Column(title: "Leave", width: 72),
        Column(title: "Travel", width: 0),
    ]

    static func render(_ report: YearPresenceReport) throws -> Data {
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let calendar = JournalCalendar.civil
        let generatedFormatter = DateFormatter()
        generatedFormatter.calendar = calendar
        generatedFormatter.timeZone = calendar.timeZone
        generatedFormatter.locale = Locale.current
        generatedFormatter.dateStyle = .long
        generatedFormatter.timeStyle = .short

        let tzLabel = report.journalTimeZoneIdentifier.replacingOccurrences(of: "_", with: " ")

        return renderer.pdfData { context in
            var pageNumber = 0
            var y = margin

            func contentWidth() -> CGFloat {
                pageRect.width - margin * 2
            }

            func travelColumnWidth() -> CGFloat {
                let fixed = columns.dropLast().reduce(0) { $0 + $1.width }
                return contentWidth() - fixed - CGFloat(columns.count - 1) * 6
            }

            func beginPage() {
                context.beginPage()
                pageNumber += 1
                y = margin
            }

            func ensureSpace(_ needed: CGFloat) {
                let limit = pageRect.height - margin - footerHeight
                if y + needed > limit {
                    drawFooter(pageNumber: pageNumber)
                    beginPage()
                }
            }

            func drawFooter(pageNumber: Int) {
                let text = "Page \(pageNumber)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: captionFont,
                    .foregroundColor: UIColor.secondaryLabel,
                ]
                let size = (text as NSString).size(withAttributes: attrs)
                let point = CGPoint(x: pageRect.width - margin - size.width, y: pageRect.height - margin + 6)
                (text as NSString).draw(at: point, withAttributes: attrs)
            }

            func textHeight(
                _ text: String,
                width: CGFloat,
                font: UIFont
            ) -> CGFloat {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .paragraphStyle: paragraph,
                ]
                let attributed = NSAttributedString(string: text, attributes: attrs)
                let bounding = attributed.boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                return max(ceil(bounding.height), 12)
            }

            func drawWrapped(
                _ text: String,
                in rect: CGRect,
                font: UIFont,
                color: UIColor = .label
            ) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph,
                ]
                let attributed = NSAttributedString(string: text, attributes: attrs)
                attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            }

            func drawLine(yPos: CGFloat) {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: yPos))
                path.addLine(to: CGPoint(x: pageRect.width - margin, y: yPos))
                UIColor.separator.setStroke()
                path.lineWidth = 0.5
                path.stroke()
            }

            func columnRects(startY: CGFloat, rowHeight: CGFloat) -> [CGRect] {
                var x = margin
                var rects: [CGRect] = []
                for (index, column) in columns.enumerated() {
                    let width = index == columns.count - 1 ? travelColumnWidth() : column.width
                    rects.append(CGRect(x: x, y: startY, width: width, height: rowHeight))
                    x += width + 6
                }
                return rects
            }

            func drawTableHeader() {
                ensureSpace(22)
                let headerY = y
                let rects = columnRects(startY: headerY, rowHeight: 16)
                for (index, column) in columns.enumerated() {
                    let title = rects[index]
                    drawWrapped(column.title, in: title, font: headerFont, color: .secondaryLabel)
                }
                y = headerY + 16
                drawLine(yPos: y)
                y += 6
            }

            func drawDayRow(_ row: YearPresenceDayRow) {
                var rowHeights: [CGFloat] = []
                let provisionalRects = columnRects(startY: 0, rowHeight: 200)

                if row.isLogged, row.segments.count >= 2 {
                    for (index, segment) in row.segments.enumerated() {
                        let locationHeight = textHeight(segment.locationLabel, width: provisionalRects[1].width, font: bodyFont)
                        let workingHeight = textHeight(segment.workingLabel, width: provisionalRects[2].width, font: bodyFont)
                        let travelText = index == 0 ? (row.tripSummary ?? "—") : "—"
                        let travelHeight = textHeight(travelText, width: provisionalRects[4].width, font: bodyFont)
                        let leaveHeight: CGFloat = index == 0
                            ? textHeight(row.leaveLabel, width: provisionalRects[3].width, font: bodyFont)
                            : 12
                        let dateHeight: CGFloat = index == 0
                            ? textHeight(row.dateLabel, width: provisionalRects[0].width, font: bodyBoldFont)
                            : 12
                        rowHeights.append(max(locationHeight, workingHeight, travelHeight, leaveHeight, dateHeight))
                    }
                } else {
                    let locationText = row.isLogged ? (row.segments.first?.locationLabel ?? "—") : "Not logged"
                    let workingText = row.workingSummary
                    let travelText = row.tripSummary ?? "—"
                    let locationHeight = textHeight(locationText, width: provisionalRects[1].width, font: bodyFont)
                    let workingHeight = textHeight(workingText, width: provisionalRects[2].width, font: bodyFont)
                    let travelHeight = textHeight(travelText, width: provisionalRects[4].width, font: bodyFont)
                    let leaveHeight = textHeight(row.leaveLabel, width: provisionalRects[3].width, font: bodyFont)
                    let dateHeight = textHeight(row.dateLabel, width: provisionalRects[0].width, font: bodyBoldFont)
                    rowHeights.append(max(locationHeight, workingHeight, travelHeight, leaveHeight, dateHeight))
                }

                let segmentCount = max(row.segments.count, 1)
                let totalHeight = rowHeights.reduce(0, +) + CGFloat(max(segmentCount - 1, 0)) * 2 + 8
                ensureSpace(totalHeight)

                let startY = y
                if row.isLogged, row.segments.count >= 2 {
                    var segmentY = startY
                    for (index, segment) in row.segments.enumerated() {
                        let height = rowHeights[index]
                        let rects = columnRects(startY: segmentY, rowHeight: height)
                        if index == 0 {
                            drawWrapped(row.dateLabel, in: rects[0], font: bodyBoldFont)
                            drawWrapped(row.leaveLabel, in: rects[3], font: bodyFont)
                            drawWrapped(row.tripSummary ?? "—", in: rects[4], font: bodyFont)
                        }
                        drawWrapped(segment.locationLabel, in: rects[1], font: bodyFont)
                        drawWrapped(segment.workingLabel, in: rects[2], font: bodyFont)
                        segmentY += height + 2
                    }
                    y = segmentY + 6
                } else {
                    let height = rowHeights[0]
                    let rects = columnRects(startY: startY, rowHeight: height)
                    let locationText = row.isLogged ? (row.segments.first?.locationLabel ?? "—") : "Not logged"
                    drawWrapped(row.dateLabel, in: rects[0], font: bodyBoldFont)
                    drawWrapped(locationText, in: rects[1], font: bodyFont, color: row.isLogged ? .label : .secondaryLabel)
                    drawWrapped(row.workingSummary, in: rects[2], font: bodyFont)
                    drawWrapped(row.leaveLabel, in: rects[3], font: bodyFont)
                    drawWrapped(row.tripSummary ?? "—", in: rects[4], font: bodyFont)
                    y = startY + height + 8
                }
                drawLine(yPos: y - 3)
            }

            beginPage()

            let title = "Presence & Working Report — \(report.year)"
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.label,
            ]
            (title as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
            y += 30

            let metaLines = [
                "Generated: \(generatedFormatter.string(from: report.generatedAt))",
                "Journal calendar timezone: \(tzLabel)",
                "Days logged: \(report.loggedDays) · Days not logged: \(report.unloggedDays) · Split travel days: \(report.splitTravelDays)",
            ]
            for line in metaLines {
                let lineHeight = textHeight(line, width: contentWidth(), font: captionFont)
                drawWrapped(line, in: CGRect(x: margin, y: y, width: contentWidth(), height: lineHeight), font: captionFont, color: .secondaryLabel)
                y += lineHeight + 2
            }
            y += 10

            let intro = """
            Day-by-day breakdown of where you were, whether you were working, any leave tags, and travel details you logged. \
            Days in two countries list each country on its own line.
            """
            let introHeight = textHeight(intro, width: contentWidth(), font: captionFont)
            drawWrapped(
                intro,
                in: CGRect(x: margin, y: y, width: contentWidth(), height: introHeight),
                font: captionFont,
                color: .secondaryLabel
            )
            y += introHeight + 16

            for month in report.months {
                ensureSpace(34)
                let monthTitle = month.monthName + " \(report.year)"
                (monthTitle as NSString).draw(
                    at: CGPoint(x: margin, y: y),
                    withAttributes: [.font: headingFont, .foregroundColor: UIColor.label]
                )
                y += 22
                drawTableHeader()

                for row in month.rows {
                    drawDayRow(row)
                }
                y += 8
            }

            drawFooter(pageNumber: pageNumber)
        }
    }

    static func exportFileURL(year: Int) throws -> URL {
        let name = "DayMemory-presence-\(year).pdf"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }
}
