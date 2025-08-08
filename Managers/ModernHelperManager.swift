//
//  ModernHelperManager.swift
//  GlassGauge
//
//  Created by Matt Zeigler on 8/8/25.
//


import Foundation
import ServiceManagement
import Security
import os.log

@available(macOS 13.0, *)
class ModernHelperManager {
    static let shared = ModernHelperManager()
    
    private let helperBundleID = "com.zeiglerstudios.glassgauge.helper"
    private let logger = Logger(subsystem: "com.zeiglerstudios.glassgauge", category: "ModernHelper")
    
    private var helperService: SMAppService?
    private var xpcConnection: NSXPCConnection?
    
    enum HelperError: Error, LocalizedError {
        case helperNotRegistered
        case connectionFailed
        case registrationFailed(Error)
        case authorizationFailed
        case notSupported
        
        var errorDescription: String? {
            switch self {
            case .helperNotRegistered:
                return "Helper daemon is not registered"
            case .connectionFailed:
                return "Failed to connect to helper daemon"
            case .registrationFailed(let error):
                return "Failed to register helper: \(error.localizedDescription)"
            case .authorizationFailed:
                return "Authorization failed - administrator privileges required"
            case .notSupported:
                return "SMAppService not supported on this macOS version"
            }
        }
    }
    
    init() {
        // Create SMAppService instance
        helperService = SMAppService.daemon(plistName: "com.zeiglerstudios.glassgauge.helper.plist")
        logger.info("🚀 ModernHelperManager initialized")
    }
    
    // MARK: - Public Interface
    
    func ensureHelperIsReady(completion: @escaping (Result<Void, Error>) -> Void) {
        logger.info("🔍 Checking helper daemon status...")
        
        guard let service = helperService else {
            completion(.failure(HelperError.notSupported))
            return
        }
        
        // Check current status
        switch service.status {
        case .enabled:
            logger.info("✅ Helper daemon already enabled")
            establishConnection(completion: completion)
            
        case .requiresApproval:
            logger.info("⚠️ Helper daemon requires approval")
            requestUserApproval(completion: completion)
            
        case .notRegistered:
            logger.info("📝 Helper daemon not registered, registering now...")
            registerHelper(completion: completion)
            
        case .notFound:
            logger.error("❌ Helper daemon not found in bundle")
            completion(.failure(HelperError.helperNotRegistered))
            
        @unknown default:
            logger.error("❌ Unknown helper daemon status")
            completion(.failure(HelperError.helperNotRegistered))
        }
    }
    
    func runPowermetrics(arguments: [String], completion: @escaping (Int32, String) -> Void) {
        ensureHelperIsReady { [weak self] result in
            switch result {
            case .success:
                self?.performPowermetricsCall(arguments: arguments, completion: completion)
            case .failure(let error):
                self?.logger.error("❌ Cannot run powermetrics: \(error.localizedDescription)")
                completion(-1, "Helper not available: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Private Implementation
    
    private func registerHelper(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let service = helperService else {
            completion(.failure(HelperError.notSupported))
            return
        }
        
        logger.info("🔐 Requesting administrative privileges for helper registration...")
        
        // Request authorization and register
        service.register { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.logger.error("❌ Helper registration failed: \(error.localizedDescription)")
                    completion(.failure(HelperError.registrationFailed(error)))
                } else {
                    self?.logger.info("✅ Helper registered successfully")
                    // Wait a moment for the service to be available
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self?.establishConnection(completion: completion)
                    }
                }
            }
        }
    }
    
    private func requestUserApproval(completion: @escaping (Result<Void, Error>) -> Void) {
        logger.info("👤 Helper requires user approval in System Settings")
        
        // Guide user to System Settings
        let alert = NSAlert()
        alert.messageText = "Helper Tool Requires Approval"
        alert.informativeText = "Please approve the GlassGauge helper tool in System Settings > General > Login Items & Extensions"
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        DispatchQueue.main.async {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open System Settings to Login Items
                if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            completion(.failure(HelperError.authorizationFailed))
        }
    }
    
    private func establishConnection(completion: @escaping (Result<Void, Error>) -> Void) {
        logger.info("🔗 Establishing XPC connection to helper daemon...")
        
        // Invalidate existing connection
        xpcConnection?.invalidate()
        
        // Create new connection
        let connection = NSXPCConnection(machServiceName: helperBundleID, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: GlassGaugeHelperProtocol.self)
        
        connection.invalidationHandler = { [weak self] in
            self?.logger.warning("⚠️ XPC connection invalidated")
            self?.xpcConnection = nil
        }
        
        connection.interruptionHandler = { [weak self] in
            self?.logger.warning("⚠️ XPC connection interrupted")
            self?.xpcConnection = nil
        }
        
        connection.resume()
        self.xpcConnection = connection
        
        // Test the connection
        testConnection(connection: connection, completion: completion)
    }
    
    private func testConnection(connection: NSXPCConnection, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let proxy = connection.remoteObjectProxy as? GlassGaugeHelperProtocol else {
            logger.error("❌ Failed to get remote proxy")
            completion(.failure(HelperError.connectionFailed))
            return
        }
        
        logger.info("🧪 Testing helper connection...")
        
        // Simple test call
        proxy.runPowermetrics(["--help"]) { [weak self] exitCode, _ in
            DispatchQueue.main.async {
                if exitCode >= 0 {
                    self?.logger.info("✅ Helper connection test successful")
                    completion(.success(()))
                } else {
                    self?.logger.error("❌ Helper connection test failed")
                    completion(.failure(HelperError.connectionFailed))
                }
            }
        }
    }
    
    private func performPowermetricsCall(arguments: [String], completion: @escaping (Int32, String) -> Void) {
        guard let connection = xpcConnection,
              let proxy = connection.remoteObjectProxy as? GlassGaugeHelperProtocol else {
            logger.error("❌ No active connection to helper")
            completion(-1, "No connection to helper")
            return
        }
        
        logger.info("📊 Running powermetrics with arguments: \(arguments)")
        
        proxy.runPowermetrics(arguments) { [weak self] exitCode, output in
            self?.logger.info("📊 Powermetrics completed with exit code: \(exitCode)")
            completion(exitCode, output)
        }
    }
    
    // MARK: - Utility Methods
    
    func getHelperStatus() -> String {
        guard let service = helperService else { return "Not supported" }
        
        switch service.status {
        case .enabled: return "Enabled"
        case .requiresApproval: return "Requires approval"
        case .notRegistered: return "Not registered"
        case .notFound: return "Not found"
        @unknown default: return "Unknown"
        }
    }
    
    func unregisterHelper(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let service = helperService else {
            completion(.failure(HelperError.notSupported))
            return
        }
        
        service.unregister { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }
}