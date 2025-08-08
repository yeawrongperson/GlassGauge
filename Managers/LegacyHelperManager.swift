//
//  LegacyHelperManager.swift
//  GlassGauge
//
//  Created by Matt Zeigler on 8/8/25.
//


import Foundation
import ServiceManagement
import Security
import os.log

// Legacy SMJobBless implementation for macOS 12 and earlier
class LegacyHelperManager {
    static let shared = LegacyHelperManager()
    
    private let helperBundleID = "com.zeiglerstudios.glassgauge.helper"
    private let logger = Logger(subsystem: "com.zeiglerstudios.glassgauge", category: "LegacyHelper")
    
    private var xpcConnection: NSXPCConnection?
    
    enum HelperError: Error, LocalizedError {
        case helperNotInstalled
        case connectionFailed
        case blessingFailed(Error)
        case authorizationFailed
        case bundleNotFound
        
        var errorDescription: String? {
            switch self {
            case .helperNotInstalled:
                return "Helper tool is not installed"
            case .connectionFailed:
                return "Failed to connect to helper"
            case .blessingFailed(let error):
                return "Failed to install helper: \(error.localizedDescription)"
            case .authorizationFailed:
                return "Authorization failed"
            case .bundleNotFound:
                return "Helper bundle not found"
            }
        }
    }
    
    // MARK: - Public Interface
    
    func ensureHelperIsReady(completion: @escaping (Result<Void, Error>) -> Void) {
        logger.info("🔍 Checking legacy helper status...")
        
        // First try to connect to existing helper
        if tryConnectToHelper() {
            logger.info("✅ Connected to existing helper")
            completion(.success(()))
            return
        }
        
        logger.info("📝 Helper not available, need to bless...")
        blessHelper(completion: completion)
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
    
    private func tryConnectToHelper() -> Bool {
        logger.info("🔗 Attempting to connect to helper: \(helperBundleID)")
        
        let connection = NSXPCConnection(machServiceName: helperBundleID, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: GlassGaugeHelperProtocol.self)
        
        var connected = false
        let semaphore = DispatchSemaphore(value: 0)
        
        connection.invalidationHandler = {
            self.logger.warning("⚠️ Helper connection invalidated")
        }
        
        connection.interruptionHandler = {
            self.logger.warning("⚠️ Helper connection interrupted")
        }
        
        connection.resume()
        
        // Test the connection with a quick call
        if let remoteProxy = connection.remoteObjectProxy as? GlassGaugeHelperProtocol {
            remoteProxy.runPowermetrics(["--help"]) { exitCode, _ in
                connected = (exitCode >= 0)
                semaphore.signal()
            }
        } else {
            semaphore.signal()
        }
        
        // Wait for response with timeout
        let result = semaphore.wait(timeout: .now() + 3.0)
        connection.invalidate()
        
        if result == .timedOut {
            logger.error("❌ Connection test timed out")
            return false
        }
        
        if connected {
            logger.info("✅ Helper connection test successful")
        }
        
        return connected
    }
    
    private func blessHelper(completion: @escaping (Result<Void, Error>) -> Void) {
        logger.info("🔐 Starting SMJobBless process...")
        
        // Validate helper bundle first
        guard validateHelperBundle() else {
            completion(.failure(HelperError.bundleNotFound))
            return
        }
        
        // Create authorization
        var authRef: AuthorizationRef?
        let authStatus = AuthorizationCreate(nil, nil, [], &authRef)
        
        guard authStatus == errAuthorizationSuccess, let auth = authRef else {
            logger.error("❌ Failed to create authorization")
            completion(.failure(HelperError.authorizationFailed))
            return
        }
        
        defer { AuthorizationFree(auth, []) }
        
        // Get administrative rights
        let rightName = kSMRightBlessPrivilegedHelper
        let rightData = rightName.data(using: .utf8)!
        
        let success = rightData.withUnsafeBytes { rightBytes in
            let rightPtr = rightBytes.bindMemory(to: CChar.self).baseAddress!
            
            var authItem = AuthorizationItem(
                name: rightPtr,
                valueLength: 0,
                value: nil,
                flags: 0
            )
            
            var authRights = AuthorizationRights(count: 1, items: &authItem)
            
            let rightStatus = AuthorizationCopyRights(
                auth,
                &authRights,
                nil,
                [.interactionAllowed, .preAuthorize, .extendRights],
                nil
            )
            
            return rightStatus == errAuthorizationSuccess
        }
        
        guard success else {
            logger.error("❌ Failed to obtain administrative rights")
            completion(.failure(HelperError.authorizationFailed))
            return
        }
        
        logger.info("✅ Administrative privileges obtained")
        
        // Perform the blessing
        performSMJobBless(with: auth, completion: completion)
    }
    
    private func performSMJobBless(with auth: AuthorizationRef, completion: @escaping (Result<Void, Error>) -> Void) {
        logger.info("🚀 Blessing helper with ID: \(helperBundleID)")
        
        var cfError: Unmanaged<CFError>?
        let success = SMJobBless(
            kSMDomainSystemLaunchd,
            helperBundleID as CFString,
            auth,
            &cfError
        )
        
        if success {
            logger.info("✅ SMJobBless succeeded")
            // Wait for helper to start
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.tryConnectToHelper() {
                    completion(.success(()))
                } else {
                    completion(.failure(HelperError.connectionFailed))
                }
            }
        } else {
            let error = cfError?.takeRetainedValue()
            let description = error.flatMap { CFErrorCopyDescription($0) as String? } ?? "Unknown error"
            logger.error("❌ SMJobBless failed: \(description)")
            completion(.failure(HelperError.blessingFailed(NSError(domain: "SMJobBless", code: -1, userInfo: [NSLocalizedDescriptionKey: description]))))
        }
    }
    
    private func validateHelperBundle() -> Bool {
        let mainBundlePath = Bundle.main.bundlePath
        let helperPath = "\(mainBundlePath)/Contents/Library/LaunchServices/\(helperBundleID)"
        
        // Check if helper bundle exists
        let helperExists = FileManager.default.fileExists(atPath: helperPath)
        if !helperExists {
            logger.error("❌ Helper bundle not found at: \(helperPath)")
            return false
        }
        
        // Check if helper executable exists
        let executablePath = "\(helperPath)/Contents/MacOS/\(helperBundleID)"
        let executableExists = FileManager.default.fileExists(atPath: executablePath)
        if !executableExists {
            logger.error("❌ Helper executable not found at: \(executablePath)")
            return false
        }
        
        logger.info("✅ Helper bundle validation passed")
        return true
    }
    
    private func performPowermetricsCall(arguments: [String], completion: @escaping (Int32, String) -> Void) {
        let connection = NSXPCConnection(machServiceName: helperBundleID, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: GlassGaugeHelperProtocol.self)
        
        connection.invalidationHandler = {
            self.logger.warning("⚠️ Connection invalidated during powermetrics call")
        }
        
        connection.interruptionHandler = {
            self.logger.warning("⚠️ Connection interrupted during powermetrics call")
        }
        
        connection.resume()
        
        guard let remoteProxy = connection.remoteObjectProxy as? GlassGaugeHelperProtocol else {
            logger.error("❌ Failed to get remote proxy for powermetrics")
            completion(-1, "Failed to connect to helper")
            connection.invalidate()
            return
        }
        
        logger.info("📊 Running powermetrics with arguments: \(arguments)")
        
        remoteProxy.runPowermetrics(arguments) { exitCode, output in
            self.logger.info("📊 Powermetrics completed with exit code: \(exitCode)")
            completion(exitCode, output)
            connection.invalidate()
        }
    }
}