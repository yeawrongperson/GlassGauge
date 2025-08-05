import Foundation

// The Mach service name must match the helper's bundle id and the Info.plist MachServices key.
let machServiceName = Bundle.main.bundleIdentifier!
let listener = NSXPCListener(machServiceName: machServiceName)
let delegate = HelperTool()
listener.delegate = delegate
listener.resume()

RunLoop.main.run()
