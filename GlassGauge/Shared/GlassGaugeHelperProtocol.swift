import Foundation

@objc public protocol GlassGaugeHelperProtocol {
    /// Runs `powermetrics` with arguments and returns (exitCode, stdout).
    func runPowermetrics(_ arguments: [String], withReply: @escaping (Int32, String) -> Void)
}
