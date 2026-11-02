import ApplicationServices
import DefiConfig
import Foundation
import Synchronization
import Testing

@testable import DefiMacOS

private func gestureConfiguration(
  invertDirection: Bool = false,
  threshold: Double = 50
) throws -> TrackpadSwipeGestureConfiguration {
  try #require(
    TrackpadSwipeGestureConfiguration(
      config: GesturesConfig(
        enabled: true,
        modifier: "alt",
        swipeThreshold: threshold,
        invertDirection: invertDirection
      ),
      aliases: [:]
    )
  )
}

private func swipe(
  _ tracker: inout TrackpadSwipeGestureTracker,
  x: Double = 0,
  y: Double = 0,
  phase: Int64,
  momentum: Int64 = 0,
  modifiersHeld: Bool = true,
  isContinuous: Bool = true
) -> TrackpadSwipeGestureTracker.Outcome {
  tracker.handle(
    deltaX: x,
    deltaY: y,
    scrollPhase: phase,
    momentumPhase: momentum,
    isContinuous: isContinuous,
    modifiersHeld: modifiersHeld
  )
}

struct TrackpadSwipeGestureTests {
  @Test
  func modifierIsRequiredAndUnmodifiedScrollPassesThrough() throws {
    var tracker = TrackpadSwipeGestureTracker(configuration: try gestureConfiguration())
    #expect(swipe(&tracker, phase: 1, modifiersHeld: false) == .passThrough)
    #expect(swipe(&tracker, x: 200, phase: 2, modifiersHeld: false) == .passThrough)
    #expect(swipe(&tracker, phase: 4, modifiersHeld: false) == .passThrough)
  }

  @Test
  func mouseWheelIsAlwaysLeftAlone() throws {
    var tracker = TrackpadSwipeGestureTracker(configuration: try gestureConfiguration())
    #expect(swipe(&tracker, y: 200, phase: 1, isContinuous: false) == .passThrough)
    #expect(swipe(&tracker, y: 200, phase: 2, isContinuous: false) == .passThrough)
  }

  @Test
  func horizontalSwipeSwallowsTheGestureAndRunsOneCommandPerThreshold() throws {
    var tracker = TrackpadSwipeGestureTracker(configuration: try gestureConfiguration())
    #expect(swipe(&tracker, x: 10, phase: 1) == .consume)
    #expect(swipe(&tracker, x: 55, phase: 2) == .run("focus-column right"))
    #expect(swipe(&tracker, x: 10, phase: 2) == .consume)
    #expect(swipe(&tracker, x: 55, phase: 2) == .run("focus-column right"))
    #expect(swipe(&tracker, phase: 4) == .consume)
  }

  @Test
  func oppositeHorizontalDirectionRunsTheOppositeCommand() throws {
    var tracker = TrackpadSwipeGestureTracker(configuration: try gestureConfiguration())
    #expect(swipe(&tracker, x: -10, phase: 1) == .consume)
    #expect(swipe(&tracker, x: -55, phase: 2) == .run("focus-column left"))
  }

  @Test
  func invertDirectionFlipsBothAxes() throws {
    var horizontal = TrackpadSwipeGestureTracker(
      configuration: try gestureConfiguration(invertDirection: true)
    )
    #expect(swipe(&horizontal, x: 10, phase: 1) == .consume)
    #expect(swipe(&horizontal, x: 55, phase: 2) == .run("focus-column left"))

    var vertical = TrackpadSwipeGestureTracker(
      configuration: try gestureConfiguration(invertDirection: true)
    )
    #expect(swipe(&vertical, y: 10, phase: 1) == .consume)
    #expect(swipe(&vertical, y: 55, phase: 2) == .run("focus-window-or-workspace up"))
  }

  @Test
  func dominantAxisKeepsTheGestureDirection() throws {
    var tracker = TrackpadSwipeGestureTracker(configuration: try gestureConfiguration())
    // A changed phase without began still tracks, e.g. after the tap restarted.
    #expect(swipe(&tracker, x: 10, y: 60, phase: 2) == .run("focus-window-or-workspace down"))
    // Later horizontal movement does not switch the axis mid-gesture.
    #expect(swipe(&tracker, x: 400, phase: 2) == .consume)
    #expect(swipe(&tracker, phase: 4) == .consume)

    var upward = TrackpadSwipeGestureTracker(configuration: try gestureConfiguration())
    #expect(swipe(&upward, y: -5, phase: 1) == .consume)
    #expect(swipe(&upward, y: -60, phase: 2) == .run("focus-window-or-workspace up"))
  }

  @Test
  func momentumAfterAConsumedGestureIsSwallowedUntilItEnds() throws {
    var tracker = TrackpadSwipeGestureTracker(configuration: try gestureConfiguration())
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
    var tracker = TrackpadSwipeGestureTracker(configuration: try gestureConfiguration())
    #expect(swipe(&tracker, x: 10, phase: 1) == .consume)
    #expect(swipe(&tracker, x: 60, phase: 2, modifiersHeld: false) == .run("focus-column right"))
    #expect(swipe(&tracker, phase: 4, modifiersHeld: false) == .consume)
  }

  @Test
  func aSecondGestureRunsAgain() throws {
    var tracker = TrackpadSwipeGestureTracker(configuration: try gestureConfiguration())
    #expect(swipe(&tracker, x: 10, phase: 1) == .consume)
    #expect(swipe(&tracker, x: 50, phase: 2) == .run("focus-column right"))
    #expect(swipe(&tracker, phase: 4) == .consume)
    #expect(swipe(&tracker, x: -10, phase: 1) == .consume)
    #expect(swipe(&tracker, x: -50, phase: 2) == .run("focus-column left"))
  }

  @Test
  func resetForgetsAnInterruptedGesture() throws {
    var tracker = TrackpadSwipeGestureTracker(configuration: try gestureConfiguration())
    #expect(swipe(&tracker, x: 40, phase: 1) == .consume)
    tracker.reset()
    // The cleared accumulation needs a fresh threshold before it can run.
    #expect(swipe(&tracker, x: 20, phase: 2) == .consume)
    #expect(swipe(&tracker, x: 40, phase: 2) == .run("focus-column right"))
  }
}

struct TrackpadSwipeGestureEventTests {
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
      gestureConfiguration: TrackpadSwipeGestureConfiguration(
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
