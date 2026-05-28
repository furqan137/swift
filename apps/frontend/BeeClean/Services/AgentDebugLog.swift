import Foundation

// #region agent log
enum AppDebugLog {
    private static let logPath = "/Users/abdulsaboor/Documents/Upwork/Projects/BeeClean/BeeClean/.cursor/debug-8c0dd4.log"
    private static let endpoint = URL(string: "http://127.0.0.1:7856/ingest/ba5275e4-4a53-4225-8b7f-d0b9e372b84c")!

    static func write(
        location: String,
        message: String,
        hypothesisId: String,
        data: [String: Any] = [:],
        runId: String = "pre-fix"
    ) {
        let payload: [String: Any] = [
            "sessionId": "8c0dd4",
            "runId": runId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let json = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: json, encoding: .utf8) else { return }

        let ndjson = line + "\n"
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(ndjson.data(using: .utf8)!)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: ndjson.data(using: .utf8))
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("8c0dd4", forHTTPHeaderField: "X-Debug-Session-Id")
        request.httpBody = json
        URLSession.shared.dataTask(with: request).resume()
    }
}
// #endregion
