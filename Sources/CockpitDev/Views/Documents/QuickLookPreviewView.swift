import SwiftUI
import QuickLookUI

/// A SwiftUI wrapper for macOS Quick Look preview using QLPreviewPanel.
/// Supports PDF, images, plain text, and markdown files.
struct QuickLookPreviewView: NSViewRepresentable {

    let url: URL

    func makeNSView(context: Context) -> QLPreviewNSView {
        let view = QLPreviewNSView(url: url)
        return view
    }

    func updateNSView(_ nsView: QLPreviewNSView, context: Context) {
        nsView.updateURL(url)
    }
}

/// Custom NSView that hosts a QLPreviewView for Quick Look previews.
class QLPreviewNSView: NSView, QLPreviewPanelDataSource {

    private var previewURL: URL
    private var qlPreviewView: NSView?

    init(url: URL) {
        self.previewURL = url
        super.init(frame: .zero)
        setupPreview()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateURL(_ url: URL) {
        if previewURL != url {
            previewURL = url
            setupPreview()
        }
    }

    private func setupPreview() {
        // Remove existing preview
        qlPreviewView?.removeFromSuperview()

        // Create a QLPreviewView
        let preview = QLPreviewView(frame: bounds, style: .normal)
        preview?.autoresizingMask = [.width, .height]
        preview?.previewItem = previewURL as QLPreviewItem
        
        if let preview {
            addSubview(preview)
            preview.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                preview.topAnchor.constraint(equalTo: topAnchor),
                preview.bottomAnchor.constraint(equalTo: bottomAnchor),
                preview.leadingAnchor.constraint(equalTo: leadingAnchor),
                preview.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
            qlPreviewView = preview
        }
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        return previewURL as QLPreviewItem
    }
}
