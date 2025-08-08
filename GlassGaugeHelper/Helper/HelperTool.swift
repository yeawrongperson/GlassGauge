import Foundation
import os.log
import Security

// Primary XPC helper implementation for powermetrics access
final class HelperTool: NSObject, GlassGaugeHelperProtocol, NSXPCListenerDelegate {
    
    private let logger = Logger(subsystem: "com.zeiglerstudios.glassgauge.helper", category: "HelperTool")
    private let listener: NSXPCListener
    
    override init() {
        // Create XPC listener with the correct service name
        listener = NSXPCListener(machServiceName: "com.zeiglerstudios.glassgauge.helper")
        super.init()
        
        logger.info("🚀 GlassGauge Helper Tool starting up...")
        listener.delegate = self
        listener.resume()
        logger.info("✅ XPC listener resumed and ready for connections")
    }
    
    // MARK: - GlassGaugeHelperProtocol
    
    func runPowermetrics(_ arguments: [String], withReply reply: @escaping (Int32, String) -> Void) {
        logger.info("📊 Received powermetrics request with arguments: \(arguments)")
        
        // Validate arguments to prevent command injection
        guard validateArguments(arguments) else {
            logger.error("❌ Invalid arguments provided: \(arguments)")
            reply(-1, "Error: Invalid arguments provided")
            return
        }
        
        // Create process
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        task.arguments = arguments
        
        // Set up pipes for output capture
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        // Set timeout
        let timeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { _ in
            if task.isRunning {
                self.logger.warning("⚠️ Powermetrics process timed out, terminating")
                task.terminate()
            }
        }
        
        do {
            try task.run()
            logger.info("✅ Powermetrics process started successfully")
            
            // Wait for completion
            task.waitUntilExit()
            timeoutTimer.invalidate()
            
            // Collect output
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            let exitCode = task.terminationStatus
            logger.info("📊 Powermetrics completed with exit code: \(exitCode), output length: \(output.count)")
            
            // Combine output and error streams
            let combinedOutput = errorOutput.isEmpty ? output : "\(output)\n\(errorOutput)"
            
            reply(exitCode, combinedOutput)
            
        } catch {
            timeoutTimer.invalidate()
            logger.error("❌ Failed to run powermetrics: \(error.localizedDescription)")
            reply(-1, "Error: Failed to execute powermetrics: \(error.localizedDescription)")
        }
    }
    
    // MARK: - NSXPCListenerDelegate
    
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        logger.info("🔗 New XPC connection request from PID: \(newConnection.processIdentifier)")
        
        // Verify the connecting process is authorized
        guard verifyConnection(newConnection) else {
            logger.error("❌ Unauthorized connection attempt from PID: \(newConnection.processIdentifier)")
            return false
        }
        
        // Set up the connection
        let interface = NSXPCInterface(with: GlassGaugeHelperProtocol.self)
        newConnection.exportedInterface = interface
        newConnection.exportedObject = self
        
        newConnection.invalidationHandler = {
            self.logger.info("ℹ️ XPC connection invalidated")
        }
        
        newConnection.interruptionHandler = {
            self.logger.warning("⚠️ XPC connection interrupted")
        }
        
        newConnection.resume()
        logger.info("✅ XPC connection accepted and configured")
        
        return true
    }
    
    // MARK: - Security and Validation
    
    private func verifyConnection(_ connection: NSXPCConnection) -> Bool {
        // Create a SecCode object for the connecting process using its PID
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: connection.processIdentifier] as CFDictionary
        let status = SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code)
        guard status == errSecSuccess, let code else {
            logger.error("❌ Failed to create SecCode from PID: \(status)")
            return false
        }

        // Requirement for the main GlassGauge application
        let requirementString = "identifier \"com.zeiglerstudios.glassgauge\" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */ and certificate leaf[subject.OU] = \"5LX3RLQKZL\""

        var secRequirement: SecRequirement?
        let reqStatus = SecRequirementCreateWithString(requirementString as CFString, SecCSFlags(), &secRequirement)
        guard reqStatus == errSecSuccess, let requirement = secRequirement else {
            logger.error("❌ Failed to create security requirement")
            return false
        }

        // Ensure the connecting process satisfies our code signing requirement
        let verifyStatus = SecCodeCheckValidity(code, SecCSFlags(), requirement)
        if verifyStatus == errSecSuccess {
            logger.info("✅ Connection verified: authorized GlassGauge app")
            return true
        } else {
            logger.error("❌ Code signature verification failed: \(verifyStatus)")
            return false
        }
    }
    
    private func validateArguments(_ arguments: [String]) -> Bool {
        // Whitelist of allowed powermetrics arguments
        let allowedArguments = Set([
            "--help", "-h",
            "--samplers", "-s",
            "--sample-count", "-n",
            "--sample-interval", "-i",
            "--show-usage-summary",
            "--show-process-coalition",
            "--show-process-gpu",
            "--show-process-energy",
            "smc", "cpu_power", "gpu_power", "thermal", "disk", "network"
        ])
        
        // Check each argument
        for arg in arguments {
            // Allow numeric values
            if Int(arg) != nil || Double(arg) != nil {
                continue
            }
            
            // Check against whitelist
            if !allowedArguments.contains(arg) {
                logger.error("❌ Disallowed argument: \(arg)")
                return false
            }
        }
        
        // Additional safety checks
        if arguments.count > 20 {
            logger.error("❌ Too many arguments provided: \(arguments.count)")
            return false
        }
        
        // Check for suspicious patterns
        for arg in arguments {
            if arg.contains("..") || arg.contains("/") || arg.contains(";") || arg.contains("&") {
                logger.error("❌ Suspicious argument pattern: \(arg)")
                return false
            }
        }
        
        return true
    }
}

// MARK: - Main Entry Point

@main
struct HelperMain {
    static func main() {
        // Set up logging
        let logger = Logger(subsystem: "com.zeiglerstudios.glassgauge.helper", category: "Main")
        
        logger.info("🚀 GlassGauge Helper Tool starting...")
        
        // Verify we're running as root
        let uid = getuid()
        if uid != 0 {
            logger.error("❌ Helper must run as root (current UID: \(uid))")
            exit(1)
        }
        
        logger.info("✅ Running as root (UID: \(uid))")
        
        // Create and start the helper tool
        _ = HelperTool()
        
        // Set up signal handling for graceful shutdown
        signal(SIGTERM) { _ in
            logger.info("📴 Received SIGTERM, shutting down gracefully")
            exit(0)
        }
        
        signal(SIGINT) { _ in
            logger.info("📴 Received SIGINT, shutting down gracefully")
            exit(0)
        }
        
        logger.info("✅ Helper tool initialized and ready")
        
        // Keep the helper running
        RunLoop.main.run()
    }
}
