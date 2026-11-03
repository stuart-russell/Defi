import DefiConfig
import DefiIPC
import Foundation

@main
struct DefiCLI {
  static func main() {
    do {
      let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
      if let service = options.service {
        try ServiceManager.run(service)
        return
      }
      if options.triage {
        try Triage.run(agent: options.triageAgent, socketURL: options.socketURL)
        return
      }
      if options.purge {
        try Uninstaller.purge()
        return
      }
      if let gestures = options.gestures {
        try GesturesCommand.run(gestures, configURL: options.configURL)
        return
      }
      guard !options.command.isEmpty else {
        print(Options.usage)
        exit(2)
      }
      let response = try sendCommand(
        options.command.joined(separator: " "),
        monitorIndex: options.monitorIndex,
        to: options.socketURL
      )
      let stream = response.ok ? FileHandle.standardOutput : FileHandle.standardError
      stream.write(Data("\(response.message)\n".utf8))
      if !response.ok { exit(1) }
    } catch {
      FileHandle.standardError.write(Data("defi: \(error)\n".utf8))
      exit(1)
    }
  }
}

struct Options {
  static let usage = """
    usage:
      defi [--socket <path>] [--monitor <index>] <command> [arguments]
      defi [--config <path>] gestures [status|enable|disable|toggle|modifier|threshold|invert|mouse-wheel|reset] [arguments]
      defi service enable|disable|start|stop|restart|status
      defi uninstall --purge
      defi triage [--agent claude|codex]

    examples:
      defi focus-column left
      defi workspace 2
      defi --monitor 2 workspace web
      defi list-workspaces --json
      defi --monitor 1 set-reserved-area top 36
      defi gestures enable
      defi gestures modifier ctrl-alt
      defi gestures threshold 80
      defi gestures status --json
      defi status
      defi trace
    """

  let socketURL: URL
  let configURL: URL
  let monitorIndex: Int?
  let command: [String]
  let gestures: [String]?
  let service: String?
  let purge: Bool
  let triage: Bool
  let triageAgent: TriageAgent?

  init(arguments: [String]) throws {
    var socketURL = SocketPath.defaultURL
    var configURL = Config.defaultURL
    var monitorIndex: Int?
    var remaining: [String] = []
    var index = 0
    while index < arguments.count {
      if arguments[index] == "--socket" {
        index += 1
        guard arguments.indices.contains(index) else { throw CLIError.usage }
        socketURL = URL(filePath: arguments[index])
      } else if arguments[index] == "--config" {
        index += 1
        guard arguments.indices.contains(index) else { throw CLIError.usage }
        configURL = URL(filePath: arguments[index])
      } else if arguments[index] == "--monitor" {
        index += 1
        guard arguments.indices.contains(index),
          let parsed = Int(arguments[index]), parsed > 0
        else {
          throw CLIError.usage
        }
        monitorIndex = parsed
      } else {
        remaining.append(arguments[index])
      }
      index += 1
    }
    var triage = false
    var triageAgent: TriageAgent?
    var gestures: [String]?
    if remaining == ["uninstall", "--purge"] {
      purge = true
      service = nil
      command = []
    } else if remaining.first == "service" {
      guard remaining.count == 2 else { throw CLIError.usage }
      purge = false
      service = remaining[1]
      command = []
    } else if remaining.first == "triage" {
      switch remaining.count {
      case 1: break
      case 3 where remaining[1] == "--agent":
        guard let agent = TriageAgent(rawValue: remaining[2]) else { throw CLIError.usage }
        triageAgent = agent
      default: throw CLIError.usage
      }
      triage = true
      purge = false
      service = nil
      command = []
    } else if remaining.first == "gestures" {
      purge = false
      service = nil
      command = []
      gestures = Array(remaining.dropFirst())
    } else {
      purge = false
      service = nil
      command = remaining
    }
    self.triage = triage
    self.triageAgent = triageAgent
    self.socketURL = socketURL
    self.configURL = configURL
    self.gestures = gestures
    self.monitorIndex = monitorIndex
  }
}

enum CLIError: Error, Equatable, CustomStringConvertible {
  case usage
  case gesturesUsage

  var description: String {
    switch self {
    case .usage: Options.usage
    case .gesturesUsage: GesturesCommand.usage
    }
  }
}
