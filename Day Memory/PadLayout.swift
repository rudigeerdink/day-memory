//
//  PadLayout.swift
//  Day Memory
//

import SwiftUI
import UIKit

enum DayMemoryLayout {
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    static func isRegularPad(_ horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        isPad && horizontalSizeClass == .regular
    }

    /// Used only to seed iPad layout before the first measurement. iPhone paths ignore it.
    static var screenWidth: CGFloat {
        let widths = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.width }
        return widths.max() ?? 1024
    }
}

/// Keeps long forms and settings readable on iPad. No effect on iPhone.
struct PadReadableColumn: ViewModifier {
    var maxWidth: CGFloat = 760

    func body(content: Content) -> some View {
        if DayMemoryLayout.isPad {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGroupedBackground))
        } else {
            content
        }
    }
}

extension View {
    func padReadableColumn(maxWidth: CGFloat = 760) -> some View {
        modifier(PadReadableColumn(maxWidth: maxWidth))
    }

    @ViewBuilder
    func padFormSheet() -> some View {
        if DayMemoryLayout.isPad {
            self.presentationSizing(.form)
        } else {
            self
        }
    }
}

/// One or two card columns, chosen from the width available to the dashboard.
struct PadCardStack<Content: View>: View {
    var columns: Int
    var spacing: CGFloat = 18
    @ViewBuilder var content: () -> Content

    var body: some View {
        if columns > 1 {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                ],
                alignment: .leading,
                spacing: 16
            ) {
                content()
            }
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                content()
            }
        }
    }
}

/// iPad dashboard scroller. Centers a single column when the window is narrow and
/// uses two columns once there is room for phone-sized cards side by side.
struct PadDashboardScroll<Content: View>: View {
    var twoColumnThreshold: CGFloat = 860
    var singleColumnMaxWidth: CGFloat = 720
    @ViewBuilder var content: (Int) -> Content

    @State private var width: CGFloat = DayMemoryLayout.screenWidth

    var body: some View {
        let columns = width >= twoColumnThreshold ? 2 : 1
        ScrollView {
            content(columns)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: columns == 1 ? singleColumnMaxWidth : .infinity)
                .frame(maxWidth: .infinity)
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { width = geo.size.width }
                    .onChange(of: geo.size.width) { _, newWidth in
                        width = newWidth
                    }
            }
        }
    }
}
