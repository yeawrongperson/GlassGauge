import Foundation
import ServiceManagement
import Security

class SMJobBlessDiagnostics {
    
    static func runCompleteDiagnostics() {
        print("🔍 === COMPREHENSIVE SMJOBBLESS DIAGNOSTICS ===")
        print()
        
        // 1. Check bundle structure
        checkBundleStructure()
        
        // 2. Check Info.plist files
        checkInfoPlists()
        
        // 3. Check code signing
        checkCodeSigning()
        
        // 4. Check current launchd state
        checkLaunchdState()
        
        // 5. Test authorization
        testAuthorization()
        
        // 6. Test manual SMJobBless with detailed error reporting
        testSMJobBlessWithDetails()
        
        print("🔍 === DIAGNOSTICS COMPLETE ===")
    }
    
    // MARK: - Bundle Structure Check
    
    static func checkBundleStructure() {
        print("📦 === BUNDLE STRUCTURE CHECK ===")
        
        let mainBundlePath = Bundle.main.bundlePath
        
        print("Main app bundle: \(mainBundlePath)")
        
        // Check if LaunchServices directory exists
        let launchServicesPath = "\(mainBundlePath)/Contents/Library/LaunchServices"
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: launchServicesPath) {
            print("✅ LaunchServices directory exists")
            
            // List contents
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: launchServicesPath)
                print("📁 LaunchServices contents: \(contents)")
                
                // Look for helper
                let helperExists = contents.contains { $0.contains("com.zeiglerstudios.glassgauge.helper") }
                if helperExists {
                    print("✅ Helper found in LaunchServices")
                    
                    // Check helper structure
                    for item in contents {
                        if item.contains("com.zeiglerstudios.glassgauge.helper") {
                            let helperPath = "\(launchServicesPath)/\(item)"
                            checkHelperStructure(at: helperPath)
                        }
                    }
                } else {
                    print("❌ Helper NOT found in LaunchServices")
                }
            } catch {
                print("❌ Cannot read LaunchServices directory: \(error)")
            }
        } else {
            print("❌ LaunchServices directory does not exist")
            print("   Expected at: \(launchServicesPath)")
            
            // Check alternative locations
            checkAlternativeHelperLocations(in: mainBundlePath)
        }
        
        print()
    }
    
    static func checkHelperStructure(at path: String) {
        print("🔍 Checking helper structure at: \(path)")
        
        let fileManager = FileManager.default

        let infoPlistPath = "\(path)/Contents/Info.plist"
        let executablePath = "\(path)/Contents/MacOS"

        if fileManager.fileExists(atPath: infoPlistPath) {
            print("  ✅ Valid bundle detected (Contents/Info.plist found)")

            if !path.hasSuffix(".app") {
                print("  ℹ️ Bundle does not use .app extension")
            }

            if fileManager.fileExists(atPath: executablePath) {
                print("  ✅ Helper MacOS directory exists")

                // Check for executable
                do {
                    let executables = try fileManager.contentsOfDirectory(atPath: executablePath)
                    print("  📁 Executables: \(executables)")
                } catch {
                    print("  ❌ Cannot read MacOS directory: \(error)")
                }
            } else {
                print("  ❌ Helper MacOS directory missing")
            }
        } else {
            print("  ❌ No valid bundle found (missing Contents/Info.plist)")
        }
    }
    
    static func checkAlternativeHelperLocations(in bundlePath: String) {
        print("🔍 Checking alternative helper locations...")
        
        let fileManager = FileManager.default
        let searchPaths = [
            "\(bundlePath)/Contents/Resources",
            "\(bundlePath)/Contents/Helpers",
            "\(bundlePath)/Contents/MacOS",
            "\(bundlePath)/Contents/Library",
            "\(bundlePath)/Contents"
        ]
        
        for searchPath in searchPaths {
            if fileManager.fileExists(atPath: searchPath) {
                do {
                    let contents = try fileManager.contentsOfDirectory(atPath: searchPath)
                    let helperItems = contents.filter { $0.contains("com.zeiglerstudios.glassgauge.helper") || $0.contains("Helper") }
                    if !helperItems.isEmpty {
                        print("  🔍 Found helper-related items in \(searchPath): \(helperItems)")
                    }
                } catch {
                    // Ignore errors for missing directories
                }
            }
        }
    }
    
    // MARK: - Info.plist Check
    
    static func checkInfoPlists() {
        print("📄 === INFO.PLIST CHECK ===")
        
        // Check main app Info.plist
        checkMainAppInfoPlist()
        
        // Check helper Info.plist
        checkHelperInfoPlist()
        
        print()
    }
    
    static func checkMainAppInfoPlist() {
        print("🔍 Main app Info.plist:")
        
        guard let infoPlistPath = Bundle.main.path(forResource: "Info", ofType: "plist") else {
            print("❌ Cannot find main app Info.plist")
            return
        }
        
        guard let infoPlist = NSDictionary(contentsOfFile: infoPlistPath) else {
            print("❌ Cannot read main app Info.plist")
            return
        }
        
        // Check bundle identifier
        if let bundleID = infoPlist["CFBundleIdentifier"] as? String {
            print("  ✅ Bundle ID: \(bundleID)")
        } else {
            print("  ❌ No bundle identifier found")
        }
        
        // Check SMPrivilegedExecutables
        if let smPrivileged = infoPlist["SMPrivilegedExecutables"] as? [String: String] {
            print("  ✅ SMPrivilegedExecutables found:")
            for (helperID, requirement) in smPrivileged {
                print("    Helper ID: \(helperID)")
                print("    Requirement: \(requirement)")
                
                // Validate requirement format
                if requirement.contains("anchor apple generic") &&
                   requirement.contains("identifier") &&
                   requirement.contains("certificate leaf[subject.OU]") {
                    print("    ✅ Requirement format looks correct")
                } else {
                    print("    ❌ Requirement format may be incorrect")
                }
            }
        } else {
            print("  ❌ SMPrivilegedExecutables not found")
        }
    }
    
    static func checkHelperInfoPlist() {
        print("🔍 Helper Info.plist:")
        
        // Find helper bundle
        guard let helperPath = findHelperBundle() else {
            print("❌ Cannot find helper bundle")
            return
        }
        
        let helperInfoPath = "\(helperPath)/Contents/Info.plist"
        guard let helperPlist = NSDictionary(contentsOfFile: helperInfoPath) else {
            print("❌ Cannot read helper Info.plist at \(helperInfoPath)")
            return
        }
        
        // Check bundle identifier
        if let bundleID = helperPlist["CFBundleIdentifier"] as? String {
            print("  ✅ Helper Bundle ID: \(bundleID)")
        } else {
            print("  ❌ No helper bundle identifier found")
        }
        
        // Check MachServices
        if let machServices = helperPlist["MachServices"] as? [String: Any] {
            print("  ✅ MachServices found:")
            for (serviceName, value) in machServices {
                print("    Service: \(serviceName) = \(value)")
            }
        } else {
            print("  ❌ MachServices not found")
        }
        
        // Check SMAuthorizedClients
        if let authorizedClients = helperPlist["SMAuthorizedClients"] as? [String] {
            print("  ✅ SMAuthorizedClients found:")
            for client in authorizedClients {
                print("    Client: \(client)")
            }
        } else {
            print("  ❌ SMAuthorizedClients not found")
        }
    }
    
    static func findHelperBundle() -> String? {
        let mainBundlePath = Bundle.main.bundlePath
        
        let possiblePaths = [
            "\(mainBundlePath)/Contents/Library/LaunchServices/com.zeiglerstudios.glassgauge.helper",
            "\(mainBundlePath)/Contents/Resources/com.zeiglerstudios.glassgauge.helper",
            "\(mainBundlePath)/Contents/Helpers/com.zeiglerstudios.glassgauge.helper"
        ]
        
        let fileManager = FileManager.default
        for path in possiblePaths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }
    
    // MARK: - Code Signing Check
    
    static func checkCodeSigning() {
        print("🔏 === CODE SIGNING CHECK ===")
        
        // Check main app signing
        let mainPath = Bundle.main.bundlePath
        checkSigningForBundle(at: mainPath, name: "Main App")
        
        // Check helper signing
        if let helperPath = findHelperBundle() {
            checkSigningForBundle(at: helperPath, name: "Helper")
        }
        
        print()
    }
    
    static func checkSigningForBundle(at path: String, name: String) {
        print("🔍 \(name) signing:")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--entitlements", "-", path]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            
            if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
                print("  Signing info:")
                let lines = errorOutput.components(separatedBy: .newlines)
                for line in lines {
                    if line.contains("Identifier=") || line.contains("TeamIdentifier=") || line.contains("Authority=") {
                        print("    \(line)")
                    }
                }
            }
            
            if let entitlements = String(data: outputData, encoding: .utf8), !entitlements.isEmpty {
                print("  Entitlements:")
                print("    \(entitlements.prefix(200))...")
            }
            
            // Verify signature
            let verifyProcess = Process()
            verifyProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            verifyProcess.arguments = ["--verify", "--verbose", path]
            
            let verifyPipe = Pipe()
            verifyProcess.standardError = verifyPipe
            
            try verifyProcess.run()
            verifyProcess.waitUntilExit()
            
            if verifyProcess.terminationStatus == 0 {
                print("  ✅ Signature verification passed")
            } else {
                print("  ❌ Signature verification failed")
                let verifyData = verifyPipe.fileHandleForReading.readDataToEndOfFile()
                if let verifyOutput = String(data: verifyData, encoding: .utf8) {
                    print("    Error: \(verifyOutput)")
                }
            }
            
        } catch {
            print("  ❌ Failed to check signing: \(error)")
        }
    }
    
    // MARK: - Launchd State Check
    
    static func checkLaunchdState() {
        print("🚀 === LAUNCHD STATE CHECK ===")
        
        let helperID = "com.zeiglerstudios.glassgauge.helper"
        
        // Check if helper is currently loaded
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list", helperID]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                if process.terminationStatus == 0 {
                    print("✅ Helper is loaded in launchd:")
                    print("  \(output)")
                } else {
                    print("ℹ️ Helper not currently loaded (this is normal)")
                }
            }
        } catch {
            print("❌ Failed to check launchctl: \(error)")
        }
        
        // Check system domain
        print("🔍 Checking system domain helpers...")
        let systemProcess = Process()
        systemProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        systemProcess.arguments = ["list"]
        
        let systemPipe = Pipe()
        systemProcess.standardOutput = systemPipe
        
        do {
            try systemProcess.run()
            systemProcess.waitUntilExit()
            
            let data = systemPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines)
                let relatedServices = lines.filter {
                    $0.contains("glassgauge") || $0.contains("GlassGauge") || $0.contains(helperID)
                }
                
                if !relatedServices.isEmpty {
                    print("  Found related services:")
                    for service in relatedServices {
                        print("    \(service)")
                    }
                } else {
                    print("  No related services found")
                }
            }
        } catch {
            print("❌ Failed to list launchctl services: \(error)")
        }
        
        print()
    }
    
    // MARK: - Authorization Test
    
    static func testAuthorization() {
        print("🔐 === AUTHORIZATION TEST ===")
        
        var authRef: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [], &authRef)
        
        if status == errAuthorizationSuccess {
            print("✅ Basic authorization creation successful")
            
            if let auth = authRef {
                // Test if we can get administrative rights
                // ✅ FIXED: Use proper string handling for AuthorizationItem
                let rightName = kAuthorizationRightExecute
                rightName.withCString { rightNameCStr in
                    var authItem = AuthorizationItem(
                        name: rightNameCStr,
                        valueLength: 0,
                        value: nil,
                        flags: 0
                    )
                    
                    // ✅ FIXED: Use withUnsafeMutablePointer to avoid inout expression issue
                    withUnsafeMutablePointer(to: &authItem) { authItemPtr in
                        var authRights = AuthorizationRights(count: 1, items: authItemPtr)
                        
                        let rightStatus = AuthorizationCopyRights(
                            auth,
                            &authRights,
                            nil,
                            [.preAuthorize],
                            nil
                        )
                        
                        if rightStatus == errAuthorizationSuccess {
                            print("✅ Administrative rights available")
                        } else {
                            print("❌ Administrative rights not available: \(rightStatus)")
                        }
                    }
                }
                
                AuthorizationFree(auth, [])
            }
        } else {
            print("❌ Authorization creation failed: \(status)")
        }
        
        print()
    }
    
    // MARK: - Detailed SMJobBless Test
    
    static func testSMJobBlessWithDetails() {
        print("🚀 === DETAILED SMJOBBLESS TEST ===")
        
        let helperID = "com.zeiglerstudios.glassgauge.helper"
        
        var authRef: AuthorizationRef?
        let authStatus = AuthorizationCreate(nil, nil, [], &authRef)
        
        guard authStatus == errAuthorizationSuccess, let auth = authRef else {
            print("❌ Cannot create authorization: \(authStatus)")
            return
        }
        
        defer { AuthorizationFree(auth, []) }
        
        print("✅ Authorization created successfully")
        print("🔧 Attempting SMJobBless with helper ID: \(helperID)")
        
        var cfError: Unmanaged<CFError>?
        let success: Bool
        
        // Handle deprecation warning - SMJobBless is deprecated in macOS 13+
        if #available(macOS 13.0, *) {
            // Note: SMAppService is recommended for macOS 13+, but for now continue with SMJobBless
            print("ℹ️ Running on macOS 13+, SMAppService is recommended but using SMJobBless for compatibility")
        }
        
        success = SMJobBless(kSMDomainSystemLaunchd, helperID as CFString, auth, &cfError)
        
        if success {
            print("✅ SMJobBless succeeded!")
        } else {
            print("❌ SMJobBless failed")
            
            if let error = cfError?.takeRetainedValue() {
                let domain = CFErrorGetDomain(error)
                let code = CFErrorGetCode(error)
                let description = CFErrorCopyDescription(error)
                
                print("  Error domain: \(domain)")
                print("  Error code: \(code)")
                
                // ✅ FIXED: Explicit string conversion for description
                if let desc = description {
                    print("  Description: \(desc as String)")
                } else {
                    print("  Description: No error description available")
                }
                
                // Provide specific guidance based on error code
                switch code {
                case 2:
                    print("  📝 Code 2 typically means:")
                    print("     - Helper bundle not found in LaunchServices")
                    print("     - Bundle identifier mismatch")
                    print("     - Code signing issues")
                    print("     - Info.plist configuration problems")
                case 3:
                    print("  📝 Code 3 typically means authorization failure")
                case 4:
                    print("  📝 Code 4 typically means the helper is already installed")
                default:
                    print("  📝 Unknown error code")
                }
            } else {
                print("  No error details available")
            }
        }
        
        print()
    }
}

// MARK: - Usage Extension

extension SMJobBlessDiagnostics {
    
    /// Call this from your SettingsView debug section
    static func runQuickDiagnostics() {
        print("\n" + String(repeating: "=", count: 50))
        print("🔍 QUICK SMJOBBLESS DIAGNOSTICS")
        print(String(repeating: "=", count: 50))
        
        checkBundleStructure()
        checkInfoPlists()
        testSMJobBlessWithDetails()
        
        print(String(repeating: "=", count: 50))
        print("🔍 DIAGNOSTICS COMPLETE")
        print(String(repeating: "=", count: 50) + "\n")
    }
    
    static func runDetailedAuthorizationTest() {
        print("🔐 === DETAILED AUTHORIZATION ANALYSIS ===")
        
        // Test basic authorization
        var authRef: AuthorizationRef?
        let authStatus = AuthorizationCreate(nil, nil, [], &authRef)
        
        guard authStatus == errAuthorizationSuccess, let auth = authRef else {
            print("❌ Cannot create basic authorization: \(authStatus)")
            return
        }
        
        defer { AuthorizationFree(auth, []) }
        
        // Test different authorization rights
        let rightsToTest = [
            kSMRightBlessPrivilegedHelper,
            "system.privilege.admin",
            "system.privileges.admin",
            "com.apple.ServiceManagement.blesshelper"
        ]
        
        for right in rightsToTest {
            print("🔍 Testing authorization right: \(right)")
            
            let rightData = right.data(using: .utf8)!
            let success = rightData.withUnsafeBytes { rightBytes in
                let rightPtr = rightBytes.bindMemory(to: CChar.self).baseAddress!
                
                var authItem = AuthorizationItem(
                    name: rightPtr,
                    valueLength: 0,
                    value: nil,
                    flags: 0
                )
                
                return withUnsafeMutablePointer(to: &authItem) { authItemPtr in
                    var authRights = AuthorizationRights(count: 1, items: authItemPtr)
                    
                    // Test with different flag combinations
                    let flagCombinations: [AuthorizationFlags] = [
                        [.interactionAllowed, .preAuthorize, .extendRights],
                        [.interactionAllowed, .extendRights],
                        [.preAuthorize],
                        []
                    ]
                    
                    for (index, flags) in flagCombinations.enumerated() {
                        let result = AuthorizationCopyRights(auth, &authRights, nil, flags, nil)
                        print("    Flags \(index + 1) (\(flags)): \(result)")
                        
                        if result == errAuthorizationSuccess {
                            print("    ✅ SUCCESS with flags: \(flags)")
                            return true
                        }
                    }
                    
                    return false
                }
            }
            
            if success {
                print("  ✅ \(right) - SUCCESS")
            } else {
                print("  ❌ \(right) - FAILED")
            }
        }
        
        // Test if we're running with elevated privileges already
        print("🔍 Checking current process privileges...")
        let uid = getuid()
        let euid = geteuid()
        print("  UID: \(uid), EUID: \(euid)")
        
        if euid == 0 {
            print("  ⚠️ Running as root - this might cause issues")
        } else if uid == euid {
            print("  ℹ️ Running as regular user - normal")
        } else {
            print("  ℹ️ Running with elevated privileges")
        }
        
        print("===========================================")
    }
    
    static func analyzeCodeSigningDetailedly() {
        print("🔏 === DETAILED CODE SIGNING ANALYSIS ===")
        
        let mainBundlePath = Bundle.main.bundlePath
        let helperPath = "\(mainBundlePath)/Contents/Library/LaunchServices/com.zeiglerstudios.glassgauge.helper"
        
        print("🔍 Main app: \(mainBundlePath)")
        print("🔍 Helper: \(helperPath)")
        
        // Check signatures in detail
        for (name, path) in [("Main App", mainBundlePath), ("Helper", helperPath)] {
            print("\n📋 \(name) detailed analysis:")
            
            // Get detailed signing info
            let infoProcess = Process()
            infoProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            infoProcess.arguments = ["-dvvvv", path]
            
            let infoPipe = Pipe()
            infoProcess.standardError = infoPipe
            
            do {
                try infoProcess.run()
                infoProcess.waitUntilExit()
                
                let data = infoPipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    print("  Signing details:")
                    for line in output.components(separatedBy: .newlines) {
                        if !line.isEmpty {
                            print("    \(line)")
                        }
                    }
                }
            } catch {
                print("  ❌ Cannot get signing info: \(error)")
            }
            
            // Check requirements
            let reqProcess = Process()
            reqProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            reqProcess.arguments = ["-dr", "-", path]
            
            let reqPipe = Pipe()
            reqProcess.standardOutput = reqPipe
            
            do {
                try reqProcess.run()
                reqProcess.waitUntilExit()
                
                let data = reqPipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    print("  Requirements:")
                    print("    \(output)")
                }
            } catch {
                print("  ❌ Cannot get requirements: \(error)")
            }
        }
        
        print("============================================")
    }
    
    static func testDirectLaunchdRegistration() {
        print("🚀 === TESTING DIRECT LAUNCHD REGISTRATION ===")
        
        let helperID = "com.zeiglerstudios.glassgauge.helper"
        
        print("🔍 Attempting to register helper directly with launchd...")
        
        // Try to load/bootstrap the service manually
        let bootstrapProcess = Process()
        bootstrapProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootstrapProcess.arguments = ["bootstrap", "system", "-", helperID]
        
        let bootstrapPipe = Pipe()
        bootstrapProcess.standardError = bootstrapPipe
        
        do {
            try bootstrapProcess.run()
            bootstrapProcess.waitUntilExit()
            
            let data = bootstrapPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                print("  Bootstrap result: \(bootstrapProcess.terminationStatus)")
                print("  Output: \(output)")
            }
        } catch {
            print("  ❌ Bootstrap failed: \(error)")
        }
        
        // Check if service is now loaded
        let listProcess = Process()
        listProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        listProcess.arguments = ["list", helperID]
        
        let listPipe = Pipe()
        listProcess.standardOutput = listPipe
        listProcess.standardError = listPipe
        
        do {
            try listProcess.run()
            listProcess.waitUntilExit()
            
            let data = listPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                print("  Service status: \(listProcess.terminationStatus)")
                print("  Details: \(output)")
            }
        } catch {
            print("  ❌ Cannot check service status: \(error)")
        }
        
        print("================================================")
    }
    
    // Call this from your SettingsView for comprehensive debugging
    static func runUltimateDebug() {
        print("\n" + String(repeating: "=", count: 80))
        print("🔍 ULTIMATE SMJOBBLESS DEBUG SESSION")
        print(String(repeating: "=", count: 80))
        
        runDetailedAuthorizationTest()
        analyzeCodeSigningDetailedly()
        testDirectLaunchdRegistration()
        runQuickDiagnostics()
        
        print(String(repeating: "=", count: 80))
        print("🔍 DEBUG SESSION COMPLETE")
        print(String(repeating: "=", count: 80) + "\n")
    }
}
