import Foundation
import Testing

@testable import DefiConfig

struct ConfigFileEditorTests {
  private func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: "defi-config-editor-\(UUID().uuidString)")
      .appending(path: "config.toml")
  }

  @Test
  func applyingChangesKeepsCommentsAndUnknownTables() throws {
    let source = """
      # my config
      [layout]
      gaps = 8 # keep this
      [custom]
      value = "keep"

      [gestures]
      enabled = false
      """

    let result = try ConfigFileEditor.applying(
      [
        .init(table: "gestures", key: "enabled", value: "true"),
        .init(table: "gestures", key: "swipe_threshold", value: "90"),
      ],
      to: source
    )

    #expect(result.config.gestures.enabled)
    #expect(result.config.gestures.swipeThreshold == 90)
    #expect(result.source.contains("# my config"))
    #expect(result.source.contains("gaps = 8 # keep this"))
    #expect(result.source.contains("[custom]"))
    #expect(result.source.contains("value = \"keep\""))
  }

  @Test
  func removingAKeyRestoresTheDefault() throws {
    let source = """
      [gestures]
      enabled = true
      modifier = "ctrl"
      """

    let result = try ConfigFileEditor.applying(
      [.init(table: "gestures", key: "modifier", value: nil)],
      to: source
    )

    #expect(result.config.gestures.modifier == GesturesConfig().modifier)
    #expect(!result.source.contains("modifier = \"ctrl\""))
  }

  @Test
  func invalidValuesLeaveTheDocumentUnchanged() throws {
    let url = temporaryURL()
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    let original = "[gestures]\nswipe_threshold = 60\n"
    try Data(original.utf8).write(to: url)

    #expect(throws: ConfigFileEditingError.invalidConfiguration("invalid value: gestures.swipe_threshold")) {
      try ConfigFileEditor.edit(
        [.init(table: "gestures", key: "swipe_threshold", value: "5")],
        at: url
      )
    }
    #expect(try String(contentsOf: url, encoding: .utf8) == original)
  }

  @Test
  func editCreatesTheFileAndParentDirectory() throws {
    let url = temporaryURL()

    let config = try ConfigFileEditor.edit(
      [
        .init(table: "gestures", key: "enabled", value: "true"),
        .init(table: "gestures", key: "modifier", value: "\"ctrl\""),
      ],
      at: url
    )

    #expect(config.gestures.enabled)
    #expect(config.gestures.modifier == "ctrl")
    let written = try String(contentsOf: url, encoding: .utf8)
    #expect(written.hasSuffix("\n"))
    #expect(written.contains("[gestures]"))
    #expect(written.contains("enabled = true"))
    #expect(written.contains("modifier = \"ctrl\""))
  }

  @Test
  func nonUTF8FileIsRejectedWithoutRewriting() throws {
    let url = temporaryURL()
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    let original = Data([0xFF, 0xFE, 0x00])
    try original.write(to: url)

    #expect(throws: ConfigFileEditingError.notUTF8) {
      try ConfigFileEditor.edit(
        [.init(table: "gestures", key: "enabled", value: "true")],
        at: url
      )
    }
    #expect(try Data(contentsOf: url) == original)
  }
}
