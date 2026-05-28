import SwiftUI
@preconcurrency import WebKit

// MARK: - Auto-Sizing WKWebView (loads images, proper dynamic height)
struct AutoSizingWebView: UIViewRepresentable {
    let html: String
    @Binding var dynamicHeight: CGFloat
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        
        webView.configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        guard !context.coordinator.hasLoaded else { return }
        context.coordinator.hasLoaded = true
        
        let styledHtml = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=3.0, user-scalable=yes">
        <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }
            html, body {
                background-color: transparent !important;
                color: #E0E0E0;
                font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', Roboto, sans-serif;
                font-size: 14px;
                line-height: 1.55;
                padding: 12px 16px;
                word-wrap: break-word;
                overflow-wrap: break-word;
                -webkit-text-size-adjust: 100%;
            }
            a { color: #64B5F6; text-decoration: none; }
            a:hover { text-decoration: underline; }
            img {
                max-width: 100% !important;
                height: auto !important;
                border-radius: 4px;
                display: block;
                margin: 4px 0;
            }
            table {
                max-width: 100% !important;
                width: auto !important;
                border-collapse: collapse;
            }
            td, th {
                word-wrap: break-word;
                overflow-wrap: break-word;
                max-width: 100vw;
            }
            table, tr, td, th, div, span, p, body {
                background-color: transparent !important;
            }
            a[style*="background"], a[class*="btn"], a[class*="button"] {
                border-radius: 6px !important;
            }
            p { margin: 6px 0; }
            h1, h2, h3, h4, h5, h6 {
                color: #FFFFFF;
                margin: 12px 0 6px 0;
            }
            pre, code {
                background: rgba(255,255,255,0.06) !important;
                padding: 6px;
                border-radius: 4px;
                overflow-x: auto;
                font-size: 12px;
                color: #B0BEC5;
            }
            blockquote {
                border-left: 2px solid #4FC3F7;
                margin: 6px 0;
                padding: 4px 12px;
                color: #9E9E9E;
            }
            hr {
                border: none;
                border-top: 1px solid rgba(255,255,255,0.08);
                margin: 8px 0;
            }
            ul, ol { padding-left: 20px; margin: 6px 0; }
            li { margin: 2px 0; }
            img[width="1"], img[height="1"],
            img[width="0"], img[height="0"] {
                display: none !important;
            }
        </style>
        </head>
        <body>
        \(html)
        <script>
        function reportHeight() {
            const h = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
            window.webkit.messageHandlers.heightChanged.postMessage(h);
        }
        window.addEventListener('load', function() {
            setTimeout(reportHeight, 200);
            setTimeout(reportHeight, 1000);
            setTimeout(reportHeight, 3000);
        });
        document.addEventListener('DOMContentLoaded', function() {
            setTimeout(reportHeight, 100);
        });
        const observer = new MutationObserver(function() {
            setTimeout(reportHeight, 100);
        });
        observer.observe(document.body, { childList: true, subtree: true, attributes: true });
        </script>
        </body>
        </html>
        """
        
        let contentController = webView.configuration.userContentController
        contentController.removeScriptMessageHandler(forName: "heightChanged")
        contentController.add(context.coordinator, name: "heightChanged")
        
        webView.loadHTMLString(styledHtml, baseURL: URL(string: "https://mail.google.com"))
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: AutoSizingWebView
        var hasLoaded = false
        
        init(parent: AutoSizingWebView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "heightChanged" else { return }
            // `message.body` is `Any` wrapping an NSNumber when JS sends a
            // number. `as? CGFloat` works via the NSNumber Obj-C bridge on
            // 64-bit iOS today, but going through NSNumber explicitly is
            // belt-and-braces: it also handles ints, doubles, and any other
            // numeric subclass the JS bridge might produce.
            let heightValue: Double?
            if let n = message.body as? NSNumber {
                heightValue = n.doubleValue
            } else if let d = message.body as? Double {
                heightValue = d
            } else {
                heightValue = nil
            }
            guard let h = heightValue, h.isFinite, h > 0 else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let newHeight = max(CGFloat(h) + 40, 200)
                if abs(newHeight - self.parent.dynamicHeight) > 10 {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.parent.dynamicHeight = newHeight
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { [weak self] result, _ in
                guard let self = self else { return }
                let heightValue: Double?
                if let n = result as? NSNumber {
                    heightValue = n.doubleValue
                } else if let d = result as? Double {
                    heightValue = d
                } else {
                    heightValue = nil
                }
                guard let h = heightValue, h.isFinite, h > 0 else { return }

                DispatchQueue.main.async {
                    let newHeight = max(CGFloat(h) + 40, 200)
                    if newHeight > self.parent.dynamicHeight {
                        self.parent.dynamicHeight = newHeight
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
