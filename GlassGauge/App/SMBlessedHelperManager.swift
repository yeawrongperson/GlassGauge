import Foundation
import ServiceManagement
import Security
import os.log

class SMBlessedHelperManager {
    static let shared = SMBlessedHelperManager()
    static let helperExecutableName: String = {
        if let executable = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String {
            return executable
        }
        if let smPrivileged = Bundle.main.object(forInfoDictionaryKey: "SMPrivilegedExecutables") as? [String: Any],
           let name = smPrivileged.keys.first {
            return name
        }
        return "com.zeiglerstudios.glassgauge.helper"
    }()
    private let helperMachServiceName = SMBlessedHelperManager.helperExecutableName
    private let helperBundleFilename = SMBlessedHelperManager.helperExecutableName
    private let logger = Logger(subsystem: "com.zeiglerstudios.glassgauge", category: "SMBlessedHelper")
    
    // Add a flag to prevent multiple simultaneous installation attempts
    private var isInstalling = false
    private let installationQueue = DispatchQueue(label: "com.glassgauge.helper.installation", qos: .utility)
    
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
        // Prevent multiple simultaneous installation attempts
        installationQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.isInstalling {
                self.logger.warning("⚠️ Helper installation already in progress")
                DispatchQueue.main.async {
                    completion(.failure(HelperError.blessingFailed(NSError(
                        domain: "SMJobBless",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Installation already in progress"]
                    ))))
                }
                return
            }
            
            self.isInstalling = true
            defer { self.isInstalling = false }
            
            self.logger.info("🔗 Starting helper blessing and connection process")
            
            // First try to connect to existing helper with timeout
            let connectionGroup = DispatchGroup()
            var connectionResult = false
            
            connectionGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                connectionResult = self.tryConnectToHelper()
                connectionGroup.leave()
            }
            
            // Wait for connection test with timeout
            let connectionTimeout = connectionGroup.wait(timeout: .now() + 5.0)
            
            if connectionTimeout == .success && connectionResult {
                self.logger.info("✅ Connected to existing helper")
                DispatchQueue.main.async {
                    completion(.success(()))
                }
                return
            }
            
            if connectionTimeout == .timedOut {
                self.logger.warning("⚠️ Connection test timed out, proceeding with blessing")
            }
            
            self.logger.info("⚙️ Helper not available, attempting to bless...")
            
            // Add overall timeout for the blessing process
            let blessingGroup = DispatchGroup()
            var blessingCompleted = false
            
            blessingGroup.enter()
            
            // Helper not available, need to bless
            self.blessHelper { [weak self] result in
                defer {
                    blessingCompleted = true
                    blessingGroup.leave()
                }
                
                switch result {
                case .success:
                    self?.logger.info("✅ Helper blessed successfully")
                    
                    // Give helper time to start, then test connection
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) {
                        if self?.tryConnectToHelper() == true {
                            self?.logger.info("✅ Connected to newly blessed helper")
                            DispatchQueue.main.async {
                                completion(.success(()))
                            }
                        } else {
                            self?.logger.error("❌ Failed to connect to newly blessed helper")
                            DispatchQueue.main.async {
                                completion(.failure(HelperError.connectionFailed))
                            }
                        }
                    }
                    
                case .failure(let error):
                    self?.logger.error("❌ Helper blessing failed: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
            
            // Wait for blessing with timeout
            let blessingTimeout = blessingGroup.wait(timeout: .now() + 30.0)
            
            if blessingTimeout == .timedOut && !blessingCompleted {
                self.logger.error("❌ Helper blessing process timed out")
                DispatchQueue.main.async {
                    completion(.failure(HelperError.blessingFailed(NSError(
                        domain: "SMJobBless",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Blessing process timed out"]
                    ))))
                }
            }
        }
    }
    
    private func tryConnectToHelper() -> Bool {
        logger.info("🔗 Attempting to connect to helper: \(self.helperMachServiceName)")
        
        let connection = NSXPCConnection(machServiceName: helperMachServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: GlassGaugeHelperProtocol.self)
        
        var connected = false
        let semaphore = DispatchSemaphore(value: 0)
        var connectionFinished = false
        
        connection.invalidationHandler = {
            self.logger.warning("⚠️ Helper connection invalidated")
            if !connectionFinished {
                connectionFinished = true
                semaphore.signal()
            }
        }
        
        connection.interruptionHandler = {
            self.logger.warning("⚠️ Helper connection interrupted")
            if !connectionFinished {
                connectionFinished = true
                semaphore.signal()
            }
        }
        
        connection.resume()
        
        // Test the connection with a quick call - use shorter timeout for individual operations
        if let remoteProxy = connection.remoteObjectProxy as? GlassGaugeHelperProtocol {
            // Use a very simple test that should complete quickly
            remoteProxy.runPowermetrics(["--help"]) { exitCode, output in
                // Don't care about the exact output, just that we got a response
                connected = true  // Any response means connection works
                self.logger.info("📊 Connection test completed with exit code: \(exitCode)")
                if !connectionFinished {
                    connectionFinished = true
                    semaphore.signal()
                }
            }
        } else {
            logger.error("❌ Failed to get remote proxy")
            if !connectionFinished {
                connectionFinished = true
                semaphore.signal()
            }
        }
        
        // Wait for response with shorter timeout to prevent hanging
        let timeout = DispatchTime.now() + .seconds(2)
        let result = semaphore.wait(timeout: timeout)
        
        // Always invalidate the connection
        connection.invalidate()
        
        if result == .timedOut {
            logger.error("❌ Connection test timed out after 2 seconds")
            connected = false
        }
        
        if connected {
            logger.info("✅ Helper connection test successful")
        } else {
            logger.error("❌ Helper connection failed")
        }
        
        return connected
    }
    
    private func blessHelper(completion: @escaping (Result<Void, Error>) -> Void) {
        // Authorization UI must be on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.logger.info("🔐 Requesting authorization for helper blessing...")
            
            // Create authorization on main thread
            let authResult = self.createAuthorization()
            
            switch authResult {
            case .success(let auth):
                self.logger.info("✅ Administrative privileges obtained")
                
                // Move SMJobBless to background thread with proper QoS
                // Use .utility instead of .userInitiated to avoid priority inversion
                DispatchQueue.global(qos: .utility).async {
                    self.performSMJobBless(with: auth, completion: completion)
                    // Free auth after use
                    AuthorizationFree(auth, [])
                }
                
            case .failure(let error):
                self.logger.error("❌ Authorization failed: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    // Separate method to handle authorization creation safely
    private func createAuthorization() -> Result<AuthorizationRef, HelperError> {
        var authRef: AuthorizationRef?
        let authStatus = AuthorizationCreate(nil, nil, [], &authRef)
        
        guard authStatus == errAuthorizationSuccess, let auth = authRef else {
            logger.error("❌ Failed to create authorization: \(authStatus)")
            return .failure(.authorizationFailed)
        }
        
        logger.info("🔐 Requesting administrative privileges...")
        
        // Create the authorization item safely without withCString closure
        let rightName = kSMRightBlessPrivilegedHelper
        let rightNameData = rightName.data(using: .utf8)!
        
        return rightNameData.withUnsafeBytes { rightNameBytes in
            let rightNamePtr = rightNameBytes.bindMemory(to: CChar.self).baseAddress!
            
            var authItem = AuthorizationItem(
                name: rightNamePtr,
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
            
            guard rightStatus == errAuthorizationSuccess else {
                logger.error("❌ Failed to obtain administrative rights: \(rightStatus)")
                AuthorizationFree(auth, [])
                return .failure(.authorizationFailed)
            }
            
            return .success(auth)
        }
    }
    
    private func performSMJobBless(with auth: AuthorizationRef, completion: @escaping (Result<Void, Error>) -> Void) {
        logger.info("🚀 Blessing helper with ID: \(self.helperMachServiceName)")
        
        // Additional validation before blessing
        let validationResult = validateHelperBundle()
        if let error = validationResult {
            logger.error("❌ Helper validation failed: \(error)")
            DispatchQueue.main.async {
                completion(.failure(HelperError.blessingFailed(error)))
            }
            return
        }
        
        // Perform the blessing - SMJobBless is deprecated in macOS 13+ but still functional
        var cfError: Unmanaged<CFError>?
        let success = SMJobBless(
            kSMDomainSystemLaunchd,
            self.helperMachServiceName as CFString,
            auth,
            &cfError
        )
        
        DispatchQueue.main.async {
            if success {
                self.logger.info("✅ SMJobBless succeeded")
                completion(.success(()))
            } else {
                let error = cfError?.takeRetainedValue()
                let domain = error.map { CFErrorGetDomain($0) as String } ?? "Unknown"
                let code = error.map { CFErrorGetCode($0) } ?? -1
                let description = error.flatMap { CFErrorCopyDescription($0) as String? } ?? "Unknown error"
                
                self.logger.error("❌ SMJobBless failed with CFError: \(description)")
                self.logger.error("   Error domain: \(domain)")
                self.logger.error("   Error code: \(code)")
                
                // Provide specific guidance based on error code
                switch code {
                case 2:
                    self.logger.error("   📝 Code 2 typically means:")
                    self.logger.error("     - Helper bundle not found in LaunchServices")
                    self.logger.error("     - Bundle identifier mismatch")
                    self.logger.error("     - Code signing issues")
                    self.logger.error("     - Info.plist configuration problems")
                case 3:
                    self.logger.error("   📝 Code 3 typically means authorization failure")
                case 4:
                    self.logger.error("   📝 Code 4 typically means the helper is already installed")
                case 8:
                    self.logger.error("   📝 Code 8 typically means:")
                    self.logger.error("     - Helper binary not found or not executable")
                    self.logger.error("     - Code signing validation failed")
                    self.logger.error("     - Helper bundle structure is incorrect")
                default:
                    self.logger.error("   📝 Unknown error code")
                }
                
                // Create proper NSError from CFError
                let nsError = self.createNSError(from: error, code: code, description: description)
                let wrappedError = HelperError.blessingFailed(nsError)
                completion(.failure(wrappedError))
            }
        }
    }
    
    // Helper method to properly convert CFError to NSError
    private func createNSError(from cfError: CFError?, code: CFIndex, description: String) -> NSError {
        if let cfError = cfError {
            let errorDomain = CFErrorGetDomain(cfError) as String
            let errorCode = Int(CFErrorGetCode(cfError))
            var userInfo: [String: Any] = [:]
            
            if let errorDescription = CFErrorCopyDescription(cfError) {
                userInfo[NSLocalizedDescriptionKey] = errorDescription as String
            }
            
            if let failureReason = CFErrorCopyFailureReason(cfError) {
                userInfo[NSLocalizedFailureReasonErrorKey] = failureReason as String
            }
            
            return NSError(domain: errorDomain, code: errorCode, userInfo: userInfo)
        } else {
            return NSError(domain: "SMJobBless", code: Int(code), userInfo: [NSLocalizedDescriptionKey: description])
        }
    }
    
    // MARK: - Helper Bundle Validation
    private func validateHelperBundle() -> Error? {
        // Get main bundle path
        let mainBundlePath = Bundle.main.bundlePath
        
        let helperPath = "\(mainBundlePath)/Contents/Library/LaunchServices/\(self.helperBundleFilename)"
        let helperInfoPlistPath = "\(helperPath)/Contents/Info.plist"
        let helperExecutablePath = "\(helperPath)/Contents/MacOS/\(self.helperBundleFilename)"
        
        // Check if helper bundle exists
        let helperExists = FileManager.default.fileExists(atPath: helperPath)
        if !helperExists {
            logger.error("❌ Helper bundle not found at: \(helperPath)")
            return NSError(domain: "SMJobBless", code: -1, userInfo: [NSLocalizedDescriptionKey: "Helper bundle not found"])
        }
        
        // Check if helper executable exists and is executable
        var isDirectory: ObjCBool = false
        let executableExists = FileManager.default.fileExists(atPath: helperExecutablePath, isDirectory: &isDirectory)
        if !executableExists || isDirectory.boolValue {
            logger.error("❌ Helper executable not found at: \(helperExecutablePath)")
            return NSError(domain: "SMJobBless", code: -1, userInfo: [NSLocalizedDescriptionKey: "Helper executable not found"])
        }
        
        // Check if executable has proper permissions
        let isExecutable = FileManager.default.isExecutableFile(atPath: helperExecutablePath)
        if !isExecutable {
            logger.error("❌ Helper executable is not executable: \(helperExecutablePath)")
            return NSError(domain: "SMJobBless", code: -1, userInfo: [NSLocalizedDescriptionKey: "Helper executable not executable"])
        }
        
        // Validate Info.plist
        guard let helperInfoPlist = NSDictionary(contentsOfFile: helperInfoPlistPath) else {
            logger.error("❌ Cannot read helper Info.plist at: \(helperInfoPlistPath)")
            return NSError(domain: "SMJobBless", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot read helper Info.plist"])
        }
        
        // Check bundle identifier
        guard let helperBundleID = helperInfoPlist["CFBundleIdentifier"] as? String else {
            logger.error("❌ Helper bundle identifier not found")
            return NSError(domain: "SMJobBless", code: -1, userInfo: [NSLocalizedDescriptionKey: "Helper bundle identifier not found"])
        }
        
        if helperBundleID != self.helperBundleFilename {
            logger.error("❌ Helper bundle identifier mismatch: expected '\(self.helperBundleFilename)', got '\(helperBundleID)'")
            return NSError(domain: "SMJobBless", code: -1, userInfo: [NSLocalizedDescriptionKey: "Helper bundle identifier mismatch"])
        }
        
        // Check MachServices
        guard let machServices = helperInfoPlist["MachServices"] as? [String: Any] else {
            logger.error("❌ Helper MachServices not found")
            return NSError(domain: "SMJobBless", code: -1, userInfo: [NSLocalizedDescriptionKey: "Helper MachServices not found"])
        }
        
        if machServices[self.helperMachServiceName] == nil {
            logger.error("❌ Helper MachServices configuration missing for service: \(self.helperMachServiceName)")
            return NSError(domain: "SMJobBless", code: -1, userInfo: [NSLocalizedDescriptionKey: "Helper MachServices missing"])
        }
        
        logger.info("✅ Helper bundle validation passed")
        return nil
    }
    
    func runPowermetrics(arguments: [String], completion: @escaping (Int32, String) -> Void) {
        ensureBlessedAndConnect { result in
            switch result {
            case .success:
                self.performPowermetricsCall(arguments: arguments, completion: completion)
            case .failure(let error):
                self.logger.error("❌ Cannot run powermetrics: \(error.localizedDescription)")
                completion(-1, "Helper not available: \(error.localizedDescription)")
            }
        }
    }
    
    private func performPowermetricsCall(arguments: [String], completion: @escaping (Int32, String) -> Void) {
        let connection = NSXPCConnection(machServiceName: self.helperMachServiceName, options: .privileged)
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
    
    // MARK: - Helper for testing connection manually
    func testConnection(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.tryConnectToHelper()
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
    
    // MARK: - Helper status check
    func isHelperInstalled() -> Bool {
        // Simple check - try to connect without blessing
        return tryConnectToHelper()
    }
}
