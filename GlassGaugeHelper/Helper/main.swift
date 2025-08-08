// main.swift (helper target)
import Foundation

let listener = NSXPCListener(machServiceName: "com.zeiglerstudios.glassgauge.helper")
let delegate = HelperTool()
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
