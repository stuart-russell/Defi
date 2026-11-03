import DefiConfig
import Foundation
import Testing

@testable import DefiCLI

private func change(_ table: String, _ key: String, _ value: String?) -> ConfigFileEditor.Change {
  ConfigFileEditor.Change(table: table, key: key, value: value)
}

struct GesturesCommandTests {
  private let defaults = Config()

  @Test
  func enableDisableAndToggleSetTheEnabledFlag() throws {
    #expect(
      try GesturesCommand.changes(for: ["enable"], current: defaults)
        == [change("gestures", "enabled", "true")]
    )
    #expect(
      try GesturesCommand.changes(for: ["disable"], current: defaults)
        == [change("gestures", "enabled", "false")]
    )
    #expect(
      try GesturesCommand.changes(for: ["toggle"], current: defaults)
        == [change("gestures", "enabled", "true")]
    )
    var enabled = defaults
    enabled.gestures.enabled = true
    #expect(
      try GesturesCommand.changes(for: ["toggle"], current: enabled)
        == [change("gestures", "enabled", "false")]
    )
  }

  @Test
  func modifierAndThresholdQuoteAndPassThroughValues() throws {
    #expect(
      try GesturesCommand.changes(for: ["modifier", "ctrl-alt"], current: defaults)
        == [change("gestures", "modifier", "\"ctrl-alt\"")]
    )
    #expect(
      try GesturesCommand.changes(for: ["threshold", "90"], current: defaults)
        == [change("gestures", "swipe_threshold", "90")]
    )
  }

  @Test
  func booleanSettingsAcceptOnOffAndToggle() throws {
    #expect(
      try GesturesCommand.changes(for: ["invert", "on"], current: defaults)
        == [change("gestures", "invert_direction", "true")]
    )
    #expect(
      try GesturesCommand.changes(for: ["mouse-wheel", "off"], current: defaults)
        == [change("gestures", "mouse_wheel", "false")]
    )
    #expect(
      try GesturesCommand.changes(for: ["invert", "toggle"], current: defaults)
        == [change("gestures", "invert_direction", "true")]
    )
  }

  @Test
  func resetRemovesOneKeyOrAllKeys() throws {
    #expect(
      try GesturesCommand.changes(for: ["reset", "threshold"], current: defaults)
        == [change("gestures", "swipe_threshold", nil)]
    )
    let all = try GesturesCommand.changes(for: ["reset"], current: defaults)
    #expect(
      Set(all.map(\.key)) == [
        "enabled", "modifier", "swipe_threshold", "invert_direction", "mouse_wheel",
      ]
    )
    #expect(all.allSatisfy { $0.value == nil })
  }

  @Test(arguments: [
    ["enable", "extra"],
    ["modifier"],
    ["modifier", ""],
    ["threshold"],
    ["threshold", "fast"],
    ["invert"],
    ["invert", "yes"],
    ["mouse-wheel", "maybe"],
    ["reset", "unknown"],
    ["reset", "threshold", "extra"],
    ["unknown"],
  ])
  func malformedArgumentsUseGestureUsage(arguments: [String]) {
    #expect(throws: CLIError.gesturesUsage) {
      try GesturesCommand.changes(for: arguments, current: defaults)
    }
  }
}

struct GesturesOptionsTests {
  @Test
  func gesturesFamilyIsParsedBeforeTheGenericCommand() throws {
    let options = try Options(arguments: ["gestures", "modifier", "alt"])

    #expect(options.gestures == ["modifier", "alt"])
    #expect(options.command.isEmpty)
  }

  @Test
  func bareGesturesCommandRequestsStatus() throws {
    let options = try Options(arguments: ["gestures"])

    #expect(options.gestures == [])
    #expect(options.command.isEmpty)
  }

  @Test
  func configPathOverridesTheDefaultLocation() throws {
    let options = try Options(arguments: ["--config", "/tmp/defi-test.toml", "gestures", "status"])

    #expect(options.configURL.path == "/tmp/defi-test.toml")
    #expect(options.gestures == ["status"])
  }

  @Test
  func configFlagRequiresAPath() {
    #expect(throws: CLIError.usage) {
      try Options(arguments: ["--config"])
    }
  }
}
