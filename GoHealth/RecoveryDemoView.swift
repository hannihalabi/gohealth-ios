import SwiftUI
import WebKit
import HealthKit

// Live data is read and calculated only on the iPhone. Demo files are separate.
struct RecoveryDemoView: UIViewRepresentable {
    enum Scope: Equatable {
        case demo
        case beta
        case account(UUID)
    }

    let health: HealthStore
    let scope: Scope
    private var demo: Bool { scope == .demo || scope == .beta }

    private static func recordURL(for scope: Scope) -> URL? {
        let filename: String
        switch scope {
        case .demo: filename = "RecoverySensorSynthetic.json"
        case .beta: return nil
        case .account(let id): filename = "RecoverySensor-\(id.uuidString).json"
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(health: health, demo: demo, recordURL: Self.recordURL(for: scope))
    }
    func makeUIView(context: Context) -> WKWebView {
        let content = WKUserContentController()
        content.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "recoveryDemo")
        var initial = "window.gohealthDemo = \(demo ? "true" : "false");"
        if let url = Self.recordURL(for: scope),
           let data = try? Data(contentsOf: url),
           let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           record["demo"] as? Bool == demo,
           let json = String(data: data, encoding: .utf8) {
            initial += "window.nativeSensorRecord = \(json);"
        }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--verify-recovery-save") { initial += "window.nativeSensorTestStrained = true;" }
        #endif
        content.addUserScript(WKUserScript(source: initial, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = content
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        if !demo {
            context.coordinator.queries = health.observeRecoveryChanges { [weak webView] in
                webView?.evaluateJavaScript("window.dispatchEvent(new Event('gohealth-sensors-changed'));")
            }
            context.coordinator.foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak webView] _ in
                webView?.evaluateJavaScript("window.dispatchEvent(new Event('gohealth-sensors-changed'));")
            }
        }
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "RecoveryDemo") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "recoveryDemo")
    }

    final class Coordinator: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
        private let health: HealthStore
        private let demo: Bool
        private let recordURL: URL?
        var queries: [HKQuery] = []
        var foregroundObserver: NSObjectProtocol?
        @MainActor func stopObserving() {
            health.stopRecoveryObservation(queries)
            if let observer = foregroundObserver { NotificationCenter.default.removeObserver(observer) }
        }
        init(health: HealthStore, demo: Bool, recordURL: URL?) {
            self.health = health
            self.demo = demo
            self.recordURL = recordURL
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage,
                                   replyHandler: @escaping (Any?, String?) -> Void) {
            guard message.frameInfo.isMainFrame,
                  message.frameInfo.request.url?.isFileURL == true,
                  let payload = message.body as? [String: Any] else {
                replyHandler(nil, "Begäran stöds inte")
                return
            }
            if payload["action"] as? String == "readSensors" {
                guard !demo else { replyHandler(nil, "Demot läser inte personliga mätningar"); return }
                Task { @MainActor in
                    do { replyHandler(try await health.recoverySensorData(), nil) }
                    catch { replyHandler(nil, "Apple Hälsa kunde inte läsas. Kontrollera appens åtkomst i Hälsa.") }
                }
                return
            }
            guard payload["action"] as? String == "saveSensorResult",
                  let record = payload["record"] as? [String: Any],
                  record["demo"] as? Bool == demo,
                  record["automatic"] as? Bool == true,
                  let result = record["result"] as? [String: Any],
                  result["modelVersion"] as? String == "gohealth-recovery-sensor-0.1-unvalidated" else {
                replyHandler(nil, "Endast automatiska sensorresultat får sparas")
                return
            }
            guard let recordURL else { replyHandler(true, nil); return }
            do {
                let url = recordURL
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try JSONSerialization.data(withJSONObject: record)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                replyHandler(true, nil)
            } catch { replyHandler(nil, "Resultatet kunde inte sparas lokalt") }
        }
        #if DEBUG && targetEnvironment(simulator)
        // Verify automatic load -> calculation -> native file and restore, with no form.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let save = ProcessInfo.processInfo.arguments.contains("--verify-recovery-save")
            let reload = ProcessInfo.processInfo.arguments.contains("--verify-recovery-reload")
            guard save || reload else { return }
            let script = """
                for (let i = 0; i < 50; i++) {
                    if (document.querySelector('[data-testid=total-score]')
                        && document.querySelector('.recovery-status').textContent.includes('Uppdaterat automatiskt.')) {
                        return {passed: !document.querySelector('form,input,select,textarea'),
                                score: Number(document.querySelector('[data-testid=total-score]').firstChild.textContent),
                                historyDays: document.querySelector('.recovery-history tbody').rows.length,
                                restoredScore: window.nativeSensorRecord?.result?.score ?? null};
                    }
                    await new Promise(resolve => setTimeout(resolve, 100));
                }
                return {passed: false, error: 'Automatic native recovery test failed'};
                """
            webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                let record: [String: Any]
                switch result {
                case .success(let value): record = value as? [String: Any] ?? ["passed": false]
                case .failure: record = ["passed": false, "error": "WebKit verification failed"]
                }
                guard let recordURL = RecoveryDemoView.recordURL(for: .demo) else { return }
                let url = recordURL.deletingLastPathComponent()
                    .appendingPathComponent(save ? "RecoveryVerifySave.json" : "RecoveryVerifyReload.json")
                if let data = try? JSONSerialization.data(withJSONObject: record) { try? data.write(to: url, options: [.atomic, .completeFileProtection]) }
            }
        }
        #endif
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
        }
    }
}
