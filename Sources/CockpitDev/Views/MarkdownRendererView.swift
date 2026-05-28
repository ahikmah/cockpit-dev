import SwiftUI
import WebKit

struct MarkdownRendererView: View {
    @Environment(\.colorScheme) private var colorScheme

    let content: String
    @State private var measuredHeight: CGFloat = 220

    var body: some View {
        MarkdownWebView(
            html: MarkdownHTMLRenderer().renderDocument(content, isDarkMode: colorScheme == .dark),
            measuredHeight: $measuredHeight
        )
        .frame(maxWidth: .infinity)
        .frame(height: measuredHeight)
    }
}

private struct MarkdownWebView: NSViewRepresentable {
    let html: String
    @Binding var measuredHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(measuredHeight: $measuredHeight)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.currentHTML != html else {
            return
        }
        context.coordinator.currentHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var measuredHeight: CGFloat
        var currentHTML: String = ""

        init(measuredHeight: Binding<CGFloat>) {
            _measuredHeight = measuredHeight
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateHeight(from: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            updateHeight(from: webView)
        }

        private func updateHeight(from webView: WKWebView) {
            webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { [weak self] result, _ in
                guard let self else { return }
                let rawHeight = (result as? NSNumber)?.doubleValue ?? 220
                let nextHeight = max(80, ceil(rawHeight) + 6)
                DispatchQueue.main.async {
                    self.measuredHeight = nextHeight
                }
            }
        }
    }
}
