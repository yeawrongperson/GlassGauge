//
//  UnifiedHelperManager.swift
//  GlassGauge
//
//  Created by Matt Zeigler on 8/8/25.
//


import Foundation
import ServiceManagement
import Security
import os.log

// Unified helper manager that chooses between modern SMAppService and legacy SMJobBless
class UnifiedHelperManager {
    static let shared = UnifiedHelperManager()
    
    private let logger = Logger(subsystem: "com.zeiglerstudios.glassgauge", category: "UnifiedHelper")
    
    enum HelperError: Error, LocalizedError {
        case helperNotAvailable
        case connectionFailed
        case installationFailed(Error)
        case authorizationFailed
        case unsupportedOS
        
        var errorDescription: String? {
            switch self {
            case .helperNotAvailable:
                return "Helper tool is not available"
            case .connectionFailed:
                return "Failed to connect to helper"
            case .installationFailed(let error):
                return "Failed to install helper: \(error.localizedDescription)"
            case .authorizationFailed:
                return "Authorization failed"
            case .unsupportedOS:
                return "Unsupported macOS version"
            }
        }
    }
    
    private var useModernAPI: Bool {
        if #available(macOS 13.0, *) {
            return true
        } else {
            return false
        }
    }
    
    // MARK: - Public Interface
    
    func ensureHelperIsReady(completion: @escaping (Result<Void, Error>) -> Void) {
        logger.info("🔄 Starting unified helper setup (Modern API: \(useModernAPI))")
        
        if useModernAPI {
            if #available(macOS 13.0, *) {
                ModernHelperManager.shared.ensureHelperIsReady { result in
                    switch result {
                    case .success:
                        self.logger.info("✅ Modern helper ready")
                        completion(.success(()))
                    case .failure(let error):
                        self.logger.error("❌ Modern helper failed: \(error.localizedDescription)")
                        completion(.failure(HelperError.installationFailed(error)))
                    }
                }
            } else {
                completion(.failure(HelperError.unsupportedOS))
            }
        } else {
            LegacyHelperManager.shared.ensureHelperIsReady { result in
                switch result {
                case .success:
                    self.logger.info("✅ Legacy helper ready")
                    completion(.success(()))
                case .failure(let error):
                    self.logger.error("❌ Legacy helper failed: \(error.localizedDescription)")
                    completion(.failure(HelperError.installationFailed(error)))
                }
            }
        }
    }
    
    func runPowermetrics(arguments: [String], completion: @escaping (Int32, String) -> Void) {
        if useModernAPI {
            if #available(macOS 13.0, *) {
                ModernHelperManager.shared.runPowermetrics(arguments: arguments, completion: completion)
            } else {
                completion(-1, "Unsupported macOS version")
            }
        } else {
            LegacyHelperManager.shared.runPowermetrics(arguments: arguments, completion: completion)
        }
    }
    
    // MARK: - Utility Methods
    
    func getHelperStatus() -> String {
        if useModernAPI {
            if #available(macOS 13.0, *) {
                return "Modern API - " + ModernHelperManager.shared.getHelperStatus()
            } else {
                return "Unsupported"
            }
        } else {
            return "Legacy API - Available"
        }
    }
    
    func unregisterHelper(completion: @escaping (Result<Void, Error>) -> Void) {
        if useModernAPI {
            if #available(macOS 13.0, *) {
                ModernHelperManager.shared.unregisterHelper(completion: completion)
            } else {
                completion(.failure(HelperError.unsupportedOS))
            }
        } else {
            // Legacy SMJobBless doesn't have direct unregister
            completion(.failure(HelperError.unsupportedOS))
        }
    }
}

// MARK: - Backwards Compatibility Wrapper

// This maintains compatibility with your existing code
class SMBlessedHelperManager {
    static let shared = SMBlessedHelperManager()
    static let helperExecutableName = "com.zeiglerstudios.glassgauge.helper"
    
    private let logger = Logger(subsystem: "com.zeiglerstudios.glassgauge", category: "CompatibilityWrapper")
    
    enum HelperError: Error, LocalizedError {
        case helperNotInstalled
        case connectionFailed
        case blessingFailed(Error)
        case authorizationFailed
        
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
            }
        }
    }
    
    func ensureBlessedAndConnect(completion: @escaping (Result<Void, Error>) -> Void) {
        logger.info("🔄 Compatibility wrapper: delegating to unified helper manager")
        
        UnifiedHelperManager.shared.ensureHelperIsReady { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                if let unifiedError = error as? UnifiedHelperManager.HelperError {
                    switch unifiedError {
                    case .connectionFailed:
                        completion(.failure(HelperError.connectionFailed))
                    case .installationFailed(let innerError):
                        completion(.failure(HelperError.blessingFailed(innerError)))
                    case .authorizationFailed:
                        completion(.failure(HelperError.authorizationFailed))
                    default:
                        completion(.failure(HelperError.helperNotInstalled))
                    }
                } else {
                    completion(.failure(HelperError.helperNotInstalled))
                }
            }
        }
    }
    
    func runPowermetrics(arguments: [String], completion: @escaping (Int32, String) -> Void) {
        UnifiedHelperManager.shared.runPowermetrics(arguments: arguments, completion: completion)
    }
    
    func testConnection(completion: @escaping (Bool) -> Void) {
        ensureBlessedAndConnect { result in
            completion(result.isSuccess)
        }
    }
    
    func isHelperInstalled() -> Bool {
        // This is a synchronous method, but our new API is async
        // Return false to trigger the async setup
        return false
    }
}

// MARK: - Result Extension

extension Result {
    var isSuccess: Bool {
        switch self {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}