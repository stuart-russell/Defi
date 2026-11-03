import DefiConfig
import Foundation

enum GesturesCommand {
  static let usage = """
    usage:
      defi gestures [status] [--json]
      defi gestures enable|disable|toggle
      defi gestures modifier <name>
      defi gestures threshold <10...400>
      defi gestures invert on|off|toggle
      defi gestures mouse-wheel on|off|toggle
      defi gestures reset [enabled|modifier|threshold|invert|mouse-wheel]

    Writes ~/.config/defi/config.toml directly; the running daemon reloads it.
    """

  private static let table = "gestures"
  private static let resetKeys: [String: String] = [
    "enabled": "enabled",
    "modifier": "modifier",
    "threshold": "swipe_threshold",
    "invert": "invert_direction",
    "mouse-wheel": "mouse_wheel",
  ]

  static func run(_ arguments: [String], configURL: URL) throws {
    switch arguments.first {
    case nil, "status":
      guard arguments.count == 1 || (arguments.count == 2 && arguments[1] == "--json")
      else { throw CLIError.gesturesUsage }
      try printStatus(configURL: configURL, json: arguments.count == 2)
    default:
      let current = try Config.load(from: configURL)
      let changes = try changes(for: arguments, current: current)
      try ConfigFileEditor.edit(changes, at: configURL)
      print("gestures updated in \(configURL.path)")
    }
  }

  /// Pure mapping from command arguments to file changes, so parsing and
  /// toggle behaviour are testable without touching a config file.
  static func changes(
    for arguments: [String],
    current: Config
  ) throws -> [ConfigFileEditor.Change] {
    let gestures = current.gestures
    switch arguments.first {
    case "enable":
      try requireSole(arguments)
      return [.init(table: table, key: "enabled", value: "true")]
    case "disable":
      try requireSole(arguments)
      return [.init(table: table, key: "enabled", value: "false")]
    case "toggle":
      try requireSole(arguments)
      return [.init(table: table, key: "enabled", value: gestures.enabled ? "false" : "true")]
    case "modifier":
      guard arguments.count == 2, !arguments[1].isEmpty else { throw CLIError.gesturesUsage }
      return [.init(table: table, key: "modifier", value: quoted(arguments[1]))]
    case "threshold":
      guard arguments.count == 2, Double(arguments[1]) != nil else {
        throw CLIError.gesturesUsage
      }
      return [.init(table: table, key: "swipe_threshold", value: arguments[1])]
    case "invert":
      return [
        try booleanChange(arguments, key: "invert_direction", current: gestures.invertDirection)
      ]
    case "mouse-wheel":
      return [
        try booleanChange(arguments, key: "mouse_wheel", current: gestures.mouseWheel)
      ]
    case "reset":
      if arguments.count == 1 {
        return resetKeys.values.map { .init(table: table, key: $0, value: nil) }
      }
      guard arguments.count == 2, let key = resetKeys[arguments[1]] else {
        throw CLIError.gesturesUsage
      }
      return [.init(table: table, key: key, value: nil)]
    default:
      throw CLIError.gesturesUsage
    }
  }

  private static func requireSole(_ arguments: [String]) throws {
    guard arguments.count == 1 else { throw CLIError.gesturesUsage }
  }

  private static func booleanChange(
    _ arguments: [String],
    key: String,
    current: Bool
  ) throws -> ConfigFileEditor.Change {
    guard arguments.count == 2 else { throw CLIError.gesturesUsage }
    let value: Bool
    switch arguments[1] {
    case "on": value = true
    case "off": value = false
    case "toggle": value = !current
    default: throw CLIError.gesturesUsage
    }
    return .init(table: table, key: key, value: value ? "true" : "false")
  }

  private static func printStatus(configURL: URL, json: Bool) throws {
    let gestures = try Config.load(from: configURL).gestures
    if json {
      let payload: [String: Any] = [
        "enabled": gestures.enabled,
        "modifier": gestures.modifier,
        "swipe_threshold": gestures.swipeThreshold,
        "invert_direction": gestures.invertDirection,
        "mouse_wheel": gestures.mouseWheel,
      ]
      let data = try JSONSerialization.data(
        withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes]
      )
      print(String(decoding: data, as: UTF8.self))
      return
    }
    guard gestures.enabled else {
      print("gestures: disabled (enable with defi gestures enable)")
      return
    }
    print(
      "gestures: enabled (modifier \(gestures.modifier)"
        + ", threshold \(number(gestures.swipeThreshold))pt"
        + ", invert \(gestures.invertDirection ? "on" : "off")"
        + ", mouse wheel \(gestures.mouseWheel ? "on" : "off"))"
    )
    print("trackpad/wheel: horizontal focus-column, vertical focus-window-or-workspace")
  }

  private static func number(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(value)
  }

  private static func quoted(_ value: String) -> String {
    "\""
      + value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      + "\""
  }
}
