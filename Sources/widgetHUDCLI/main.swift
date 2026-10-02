import Foundation
import HUDKit

// `widgethud <command> [key=value ...]`: talks to widgetHUD's MacHUD control socket.
//
//   widgethud hello
//   widgethud say text="hi there"
//   widgethud panel toggle id=main
//   widgethud settings set showCount=0
//   widgethud quit

let usage = """
usage: widgethud <command> [key=value ...]
  hello | state | help | quit
  panel show|hide|toggle id=main
  panel frame id=main x= y= w= h=
  say [text=]                        change what the panel says (empty: back to the greeting)
  settings get [key=]  |  settings set key=value ...

Environment: WIDGETHUD_SOCKET picks the socket name (default widgethud).

"""

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first, !["-h", "--help"].contains(command) else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(arguments.isEmpty ? 2 : 0)
}

let socketName = ProcessInfo.processInfo.environment["WIDGETHUD_SOCKET"].flatMap { $0.isEmpty ? nil : $0 } ?? "widgethud"

switch command {
case "say":
    // Shorthand for `action name=say ...`.
    arguments = ["action", "name=say"] + arguments.dropFirst()
case "settings" where arguments.count > 1 && ["get", "set"].contains(arguments[1]):
    // The sub-verb travels as `action=` so the router does not read a positional as a key.
    arguments[1] = "action=\(arguments[1])"
default:
    break
}

exit(HUDSocketClient.runCLI(path: HUDSocket.path(for: socketName), arguments: arguments, appName: "widgethud"))
