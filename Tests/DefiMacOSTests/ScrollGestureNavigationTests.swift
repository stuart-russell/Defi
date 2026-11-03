import ApplicationServices
import DefiConfig
import Foundation
import Synchronization
import Testing

@testable import DefiMacOS

private func gestureConfiguration(
  invertDirection: Bool = false,
  threshold: Double = 50,
  mouseWheel: Bool = true
) throws -> ScrollGestureConfiguration {
  try #require(
    ScrollGestureConfiguration(
      config: GesturesConfig(
        enabled: true,
        modifier: "alt",
        swipeThreshold: threshold,
        invertDirection: invertDirection,
        mouseWheel: mouseWheel
      ),
      aliases: [:]
    )
  )
}

private func swipe(
  _ tracker: inout ScrollGestureTracker,
  x: Double = 0,
  y: Double = 0,
  phase: Int64,
  momentum: Int64 = 0,
  modifiersHeld: Bool = true
) -> ScrollGestureTracker.Outcome {
  tracker.handle(
    deltaX: x,
    deltaY: y,
    scrollPhase: phase,
    momentumPhase: momentum,
    isContinuous: true,
    modifiersHeld: modifiersHeld
  )
}

private func wheel(
  _ tracker: inout ScrollGestureTracker,
  x: Double = 0,
  y: Double = 0,
  modifiersHeld: Bool = true
) -> ScrollGestureTracker.Outcome {
  tracker.handle(
    deltaX: x,
    deltaY: y,
    scrollPhase: 0,
    momentumPhase: 0,
    isContinuous: false,
    modifiersHeld: modifiersHeld
  )
}

struct ScrollGestureTests {
  @Test
  func modifierIsRequiredAndUnmodifiedScrollPassesThrough() throws {
    var tracker = ScrollGestureTracker(configuration: try gestureConfiguration())
    #expect(swipe(&tracker, phase: 1, modifiersHeld: false) == .passThrough)
    #expect(swipe(&tracker, x: 200, phase: 2, modifiersHeld: false) == .passThrough)
    #expect(swipe(&tracker, phase: 4, modifiersHeld: false) == .passThrough)
  }

  @Test
  func mouseWheelVerticalFocusesWorkspacesOneNotchAtATime() throws {
    var tracker = ScrollGestureTracker(configuration: try gestureConfiguration())
    #expect(wheel(&tracker, y: 1) == .run("focus-workspace up"))
    #expect(wheel(&tracker, y: 1) == .run("focus-workspace up"))
    #expect(wheel(&tracker, y: -1) == .run("focus-workspace down"))
  }

  @Test
  func mouseWheelHorizontalFocusesColumns() throws {
    var tracker = ScrollGestureTracker(configuration: try gestureConfiguration())
    #expect(wheel(&tracker, x: 1) == .run("focus-column right"))
    #expect(wheel(&tracker, x: -1) == .run("focus-column left"))
  }

  @Test
  func mouseWheelRequiresTheConfiguredModifier() throws {
    var tracker = ScrollGestureTracker(configuration: try gestureConfiguration())
    #expect(wheel(&tracker, y: 1, modifiersHeld: false) == .passThrough)
    #expect(wheel(&tracker, x: 1, modifiersHeld: false) == .passThrough)
  }

  @Test
  func mouseWheelCanBeDisabled() throws {
    var tracker = ScrollGestureTracker(
      configuration: try gestureConfiguration(mouseWheel: false)
    )
    #expect(wheel(&tracker, y: 1) == .passThrough)
    #expect(wheel(&tracker, x: 1) == .passThrough)
  }

  @Test
  func fractionalWheelDeltasAccumulateToOneStep() throws {
    var tracker = ScrollGestureTracker(configuration: try gestureConfiguration())
    #expect(wheel(&tracker, y: 0.4) == .consume)
    #expect(wheel(&tracker, y: 0.4) == .consume)
    #expect(wheel(&tracker, y: 0.4) == .run("focus-workspace up"))
    #expect(wheel(&tracker, y: 0.4) == .consume)
  }

  @Test
  func acceleratedNotchRunsOneStepPerEvent() throws {
    var tracker = ScrollGestureTracker(configuration: try gestureConfiguration())
    #expect(wheel(&tracker, y: 3) == .run("focus-workspace up"))
    #expect(wheel(&tracker, y: 0) == .consume)
    #expect(wheel(&tracker, y: 3) == .run("focus-workspace up"))
  }

  @Test
  func invertDirectionAlsoFlipsTheWheel() throws {
    var tracker = ScrollGestureTracker(
      configuration: try gestureConfiguration(invertDirection: true)
    )
    #expect(wheel(&tracker, y: 1) == .run("focus-workspace down"))
    #expect(wheel(&tracker, x: 1) == .run("focus-column left"))
  }

  @Test
  func horizontalSwipeSwallowsTheGestureAndRunsOneCommandPerThreshold() throws {
    var tracker = ScrollGestureTracker(configuration: try gestureConfiguration())
    #expect(swipe(&tracker, x: 10, phase: 1) == .consume)
    #expect(swipe(&tracker, x: 55, phase: 2) == .run("focus-column right"))
    #expect(swipe(&tracker, x: 10, phase: 2) == .consume)
    #expect(swipe(&tracker, x: 55, phase: 2) == .run("focus-column right"))
    #expect(swipe(&tracker, phase: 4) == .consume)
  }

  @Test
  func oppositeHorizontalDirectionRunsTheOppositeCommand() throws {
    var tracker = ScrollGestureTracker(configuration: try gestureConfiguration())
    #expect(swipe(&tracker, x: -10, phase: 1) == .consume)
    #expect(swipe(&tracker, x: -55, phase: 2) == .run("focus-column left"))
  }

  @Test
  func invertDirectionFlipsBothAxes() throws {
    var horizontal = ScrollGestureTracker(
      configuration: try gestureConfiguration(invertDirection: true)
    )
    #expect(swipe(&horizontal, x: 10, phase: 1) == .consume)
    #expect(swipe(&horizontal, x: 55, phase: 2) == .run("focus-column left"))

    var vertical = ScrollGestureTracker(
      configuration: try gestureConfiguration(invertDirection: true)
    )
    #expect(swipe(&vertical, y: 10, phase: 1) == .consume)
    #expect(swipe(&vertical, y: 55, phase: 2) == .run("focus-window-or-workspace down"))
  }

  @Test
  func dominantAxisKeepsTheGestureDirection() throws {
    var tracker = ScrollGestureTracker(configuration: try gestureConfiguration())
    // A changed phase without began still tracks, e.g. after the tap restarted.
    #expect(swipe(&tracker, x: 10, y: 60, phase: 2) == .run("focus-window-or-workspace up"))
    // Later horizontal movement does not switch the axis mid-gesture.
    #expect(swipe(&tracker, x: 400, phase: 2) == .consume)
    #expect(swipe(&tracker, phase: 4) == .consume)

    var downward = ScrollGestureTracker(configuration: try gestureConfiguration())
    #expect(swipe(&downward, y: -5, phase: 1) == .consume)
    #expect(swipe(&downward, y: -60, phase: 2) == .run("focus-window-or-workspace down"))
  }

  @Test
  func momentumAfterAConsumedGestureIsSwallowedUntilItEnds() throws {
    var tracker = ScrollGestureTracker(configuration: try gestureConfiguration())
    #expect(swipe(&tracker, x: 10, phase: 1) == .consume)
    #expect(swipe(&tracker, x: 60, phase: 2) == .run("focus-column right"))
    #expect(swipe(&tracker, phase: 4) == .consume)
    #expect(swipe(&tracker, x: 30, phase: 0, momentum: 1) == .consume)
    #expect(swipe(&tracker, x: 20, phase: 0, momentum: 2) == .consume)
    #expect(swipe(&tracker, phase: 0, momentum: 4) == .consume)
    // A later scroll that Defi did not consume must reach the application.
    #expect(swipe(&tracker, x: 30, phase: 0, momentum: 2) == .passThrough)
  }

  @Test
  func releasingTheModifierMidGestureKeepsTheRemainder() throws {
    var tracker = ScrollGestureTracker(configuration: try gestureConfiguration())
    #expect(swipe(&tracker, x: 10, phase: 1) == .consume)
    #expect(swipe(&tracker, x: 60, phase: 2, modifiersHeld: false) == .run("focus-column right"))
    #expect(swipe(&tracker, phase: 4, modifiersHeld: false) == .consume)
  }

  @Test
  func aSecondGestureRunsAgain() throws {
    var tracker = ScrollGestureTracker(configuration: try gestureConfiguration())
    #expect(swipe(&tracker, x: 10, phase: 1) == .consume)
    #expect(swipe(&tracker, x: 50, phase: 2) == .run("focus-column right"))
    #expect(swipe(&tracker, phase: 4) == .consume)
    #expect(swipe(&tracker, x: -10, phase: 1) == .consume)
    #expect(swipe(&tracker, x: -50, phase: 2) == .run("focus-column left"))
  }

  @Test
  func resetForgetsAnInterruptedGesture() throws {
    var tracker = ScrollGestureTracker(configuration: try gestureConfiguration())
    #expect(swipe(&tracker, x: 40, phase: 1) == .consume)
    tracker.reset()
    // The cleared accumulation needs a fresh threshold before it can run.
    #expect(swipe(&tracker, x: 20, phase: 2) == .consume)
    #expect(swipe(&tracker, x: 40, phase: 2) == .run("focus-column right"))
  }
}

struct ScrollGestureEventTests {
  private final class CommandRecorder: Sendable {
    private let commands = Mutex<[String]>([])

    var values: [String] { commands.withLock { $0 } }

    func record(_ command: String) {
      commands.withLock { $0.append(command) }
    }
  }

  private struct Harness {
    let monitor: InputMonitor
    let recorder: CommandRecorder
  }

  private func makeMonitor(gestures: GesturesConfig) -> Harness {
    let recorder = CommandRecorder()
    let context = InputMonitor(
      bindings: [:],
      userInputTracker: UserInputTracker(),
      pointerMotionTracker: PointerMotionTracker(),
      tracksPointerWindowTransitions: false,
      gestureConfiguration: ScrollGestureConfiguration(
        config: gestures, aliases: [:]
      ),
      deliver: { invocation in recorder.record(invocation.command) },
      deliverOverview: { _ in },
      deliverPointerMotion: { _ in },
      tapReenabled: { _ in }
    )
    return Harness(monitor: context, recorder: recorder)
  }

  private func scrollEvent(
    x: Double = 0,
    y: Double = 0,
    phase: Int64,
    modifiers: CGEventFlags = .maskAlternate
  ) throws -> CGEvent {
    let event = try #require(
      CGEvent(
        scrollWheelEvent2Source: nil, units: .pixel,
        wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0
      )
    )
    event.flags = modifiers
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
    event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: y)
    event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: x)
    return event
  }

  @Test
  func modifierSwipeIsConsumedAndRunsTheNavigationCommand() throws {
    let harness = makeMonitor(
      gestures: GesturesConfig(enabled: true, modifier: "alt", swipeThreshold: 50)
    )
    #expect(harness.monitor.intercept(
      type: .scrollWheel, event: try scrollEvent(x: 10, phase: 1)
    ) == nil)
    #expect(harness.monitor.intercept(
      type: .scrollWheel, event: try scrollEvent(x: 60, phase: 2)
    ) == nil)
    #expect(harness.monitor.intercept(
      type: .scrollWheel, event: try scrollEvent(phase: 4)
    ) == nil)
    #expect(harness.recorder.values == ["focus-column right"])
  }

  private func mouseWheelEvent(
    x: Double = 0,
    y: Double = 0,
    modifiers: CGEventFlags = .maskAlternate
  ) throws -> CGEvent {
    let event = try #require(
      CGEvent(
        scrollWheelEvent2Source: nil, units: .line,
        wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0
      )
    )
    event.flags = modifiers
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0)
    event.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: y)
    event.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: x)
    return event
  }

  @Test
  func modifierMouseWheelIsConsumedAndRunsWorkspaceNavigation() throws {
    let harness = makeMonitor(
      gestures: GesturesConfig(enabled: true, modifier: "alt", swipeThreshold: 50)
    )
    #expect(harness.monitor.intercept(
      type: .scrollWheel, event: try mouseWheelEvent(y: 1)
    ) == nil)
    #expect(harness.monitor.intercept(
      type: .scrollWheel, event: try mouseWheelEvent(x: 1)
    ) == nil)
    #expect(harness.recorder.values == ["focus-workspace up", "focus-column right"])
  }

  @Test
  func mouseWheelOppositeDirectionRunsTheOppositeCommand() throws {
    let harness = makeMonitor(
      gestures: GesturesConfig(enabled: true, modifier: "alt", swipeThreshold: 50)
    )
    #expect(harness.monitor.intercept(
      type: .scrollWheel, event: try mouseWheelEvent(y: -1)
    ) == nil)
    #expect(harness.recorder.values == ["focus-workspace down"])
  }

  @Test
  func unmodifiedScrollReachesTheApplication() throws {
    let harness = makeMonitor(
      gestures: GesturesConfig(enabled: true, modifier: "alt", swipeThreshold: 50)
    )
    #expect(harness.monitor.intercept(
      type: .scrollWheel,
      event: try scrollEvent(x: 200, phase: 2, modifiers: [])
    ) != nil)
    #expect(harness.recorder.values.isEmpty)
  }

  @Test
  func disabledGesturesLeaveScrollEventsAlone() throws {
    let harness = makeMonitor(gestures: GesturesConfig(enabled: false))
    #expect(harness.monitor.intercept(
      type: .scrollWheel, event: try scrollEvent(x: 200, phase: 2)
    ) != nil)
    #expect(harness.recorder.values.isEmpty)
  }
}
