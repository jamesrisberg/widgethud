import Foundation
import HUDKit

// `widgethud <command> [key=value ...]`: talks to widgetHUD's MacHUD control socket.
//
//   widgethud hello
//   widgethud widget create instance=a type=clock frame=40,40,170,170 settings='{"timeZone":"Tokyo"}'
//   widgethud widget edit on
//   widgethud places Portland, Maine
//   widgethud settings set temperatureUnit=celsius
//   widgethud quit

let usage = """
usage: widgethud <command> [key=value ...]
  hello | state | help | menu | quit
  widget list
  widget create instance= type=clock|weather|calendar [size=] [frame=x,y,w,h] [layer=desktop|float] [settings=<json>]
  widget update instance= [size=] [frame=] [layer=] [settings=<json>]
  widget remove instance=
  widget sync instances=<json array> [editing=on|off] [revealed=on|off]
  widget edit on|off  |  widget reveal on|off  |  widget schema type=
  refresh                            fetch weather and reload calendars now
  places <place>                     look a place up with Open-Meteo (what a weather widget would show)
  status                             instances, weather places, Calendar access
  settings get [key=]  |  settings set temperatureUnit=auto|celsius|fahrenheit timeFormat=auto|12h|24h

Environment: WIDGETHUD_SOCKET picks the socket name (default widgethud).

"""

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first, !["-h", "--help"].contains(command) else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(arguments.isEmpty ? 2 : 0)
}

let socketName = ProcessInfo.processInfo.environment["WIDGETHUD_SOCKET"].flatMap { $0.isEmpty ? nil : $0 } ?? "widgethud"

switch command {
case "refresh", "status":
    // Shorthands for `action name=<verb>`.
    arguments = ["action", "name=\(command)"] + arguments.dropFirst()
case "places":
    // The words after it are the place: `widgethud places Portland, Maine`.
    let rest = arguments.dropFirst()
    let query = rest.first { $0.hasPrefix("query=") }.map { String($0.dropFirst(6)) } ?? rest.joined(separator: " ")
    arguments = ["action", "name=places", "query=\(query)"]
case "settings" where arguments.count > 1 && ["get", "set"].contains(arguments[1]):
    // The sub-verb travels as `action=` so the router does not read a positional as a key.
    arguments[1] = "action=\(arguments[1])"
default:
    break
}

exit(HUDSocketClient.runCLI(path: HUDSocket.path(for: socketName), arguments: arguments, appName: "widgethud"))
