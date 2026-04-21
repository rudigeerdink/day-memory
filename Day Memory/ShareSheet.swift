//
//  ShareSheet.swift
//  Day Memory
//

import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // iPad: an anchor is required or the share UI can appear as an empty sheet.
        guard let popover = uiViewController.popoverPresentationController else { return }
        if popover.sourceView == nil {
            popover.sourceView = uiViewController.view
            let b = uiViewController.view.bounds
            let x = b.midX
            let y = b.midY
            popover.sourceRect = CGRect(x: x, y: y, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
    }
}
