import Foundation

// A tiny command-line front end that drives the Forelight app through its
// `forelight://` URL scheme.

let arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func printUsage() {
    print("""
    usage: forelight-cli <command> [options]

      toggle                     toggle dimming on or off
      enable | disable           turn dimming on or off
      snooze [minutes]           pause dimming (default 30 minutes)
      resume                     cancel a snooze
      intensity <0.1-0.9>        set the global dim intensity
      appearance <system|light|dark>
      url <forelight://...>      open a raw URL
    """)
}

guard let command = arguments.first else {
    printUsage()
    exit(0)
}

var components = URLComponents()
components.scheme = "forelight"

switch command {
case "toggle", "enable", "disable", "resume":
    components.host = command

case "snooze":
    components.host = "snooze"
    if let minutes = arguments.dropFirst().first {
        components.queryItems = [URLQueryItem(name: "minutes", value: minutes)]
    }

case "intensity":
    guard let value = arguments.dropFirst().first else { fail("intensity needs a value") }
    components.host = "intensity"
    components.queryItems = [URLQueryItem(name: "value", value: value)]

case "appearance":
    guard let mode = arguments.dropFirst().first else { fail("appearance needs a mode") }
    components.host = "appearance"
    components.queryItems = [URLQueryItem(name: "mode", value: mode)]

case "url":
    guard let raw = arguments.dropFirst().first else { fail("url needs a value") }
    openURLString(raw)
    exit(0)

case "-h", "--help", "help":
    printUsage()
    exit(0)

default:
    fail("unknown command: \(command)")
}

guard let url = components.url else { fail("could not build a URL") }
openURLString(url.absoluteString)

func openURLString(_ urlString: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-g", urlString]
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        fail("could not open \(urlString): \(error.localizedDescription)")
    }
}
