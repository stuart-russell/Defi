import AppKit
import DefiModel
import Testing

@testable import DefiMacOS

@MainActor
struct RibbonProxyRecordingTests {
  @Test func settingsSwitchSharesOverlayWithScreenRecordings() throws {
    let renderer = RibbonProxyRenderer.shared
    let status = DefiSettingsRuntimeStatus.shared
    defer { status.animationsInRecordings = false; renderer.enabled = false }
    func sharingStates() -> [NSWindow.SharingType] {
      renderer.surfaceWindowIDs.compactMap { NSApplication.shared.window(withWindowNumber: Int($0))?.sharingType }
    }
    let readOnly = NSWindow.SharingType.readOnly
    let none = NSWindow.SharingType.none

    status.animationsInRecordings = true
    renderer.enabled = true
    _ = try #require(renderer.prepareSurface(
      area: Rect(x: 0, y: 0, width: 200, height: 200), display: CGMainDisplayID()))
    // One overlay exists per display, so this asserts the state of every surface.
    #expect(!sharingStates().isEmpty)
    #expect(sharingStates().allSatisfy { $0 == readOnly })

    status.animationsInRecordings = false
    #expect(sharingStates().allSatisfy { $0 == none })
    status.animationsInRecordings = true
    #expect(sharingStates().allSatisfy { $0 == readOnly })
  }
}
