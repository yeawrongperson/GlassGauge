import Foundation

final class HelperTool: NSObject, GlassGaugeHelperProtocol, NSXPCListenerDelegate {

    // MARK: - GlassGaugeHelperProtocol

    func runPowermetrics(_ arguments: [String], withReply: @escaping (Int32, String) -> Void) {
        let task = Process()
        task.launchPath = "/usr/bin/powermetrics"
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        task.launch()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        withReply(task.terminationStatus, output)
    }

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let iface = NSXPCInterface(with: GlassGaugeHelperProtocol.self)
        newConnection.exportedInterface = iface
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }
}

