import Foundation

// MARK: - Backend Configuration
/// Central place for the backend URL.
///
/// - **Simulator**: Uses `localhost` automatically (no config needed).
/// - **Real device**: Uses your Mac's local IP over Wi-Fi.
///
/// To find your Mac's IP:
///   System Settings → Wi-Fi → Details → IP Address
///   Then update `devMachineIP` below.
enum BackendConfig {
    /// Your Mac's local network IP for real-device testing.
    /// Find it: System Settings → Wi-Fi → Details → IP Address
    private static let devMachineIP = "10.32.31.9"
    private static let port = "3001"

    static var baseURL: String {
        #if DEBUG
            #if targetEnvironment(simulator)
            return "http://localhost:\(port)"
            #else
            return "http://\(devMachineIP):\(port)"
            #endif
        #else
        return "https://beecleanbackend-production.up.railway.app"
        #endif
    }
}
