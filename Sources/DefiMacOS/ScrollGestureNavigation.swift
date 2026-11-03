import CoreGraphics
import DefiConfig

/// A modifier plus trackpad swipe or mouse wheel scroll that becomes existing
/// navigation commands.
///
/// The gesture is opt-in and never steals a scroll the user did not reserve for
/// Defi: a scroll is consumed only while the configured modifier is held, and
/// the caller decides whether an unmodified scroll is passed through.
struct ScrollGestureConfiguration: Equatable, Sendable {
  let modifierBits: UInt64
  let swipeThreshold: Double
  let invertDirection: Bool
  let mouseWheel: Bool

  init?(config: GesturesConfig, aliases: [String: String]) {
    guard config.enabled,
      let modifier = try? Key(accelerator: "\(config.modifier)-a", aliases: aliases),
      modifier.modifierBits != 0,
      config.swipeThreshold.isFinite,
      config.swipeThreshold > 0
    else { return nil }
    modifierBits = modifier.modifierBits
    swipeThreshold = config.swipeThreshold
    invertDirection = config.invertDirection
    mouseWheel = config.mouseWheel
  }
}

/// Accumulates scroll input and emits at most one command per threshold step.
/// Accumulating here keeps platform event handling thin and lets the mapping be
/// tested without Accessibility permission.
///
/// Two input families share one modifier:
/// - Continuous trackpad scrolls use their phase and point deltas.
/// - Discrete mouse wheel notches use line deltas and a one-line step.
///
/// Deltas are the values macOS reports: positive means right and up for the
/// classic non-inverted direction. `invertDirection` flips both devices
/// consistently, whichever way the user's natural-scrolling setting points.
struct ScrollGestureTracker {
  enum Outcome: Equatable {
    /// Leave the event for the application.
    case passThrough
    /// Swallow the event without running a command.
    case consume
    /// Swallow the event and run the command.
    case run(String)
  }

  private enum Axis {
    case horizontal
    case vertical
  }

  private let configuration: ScrollGestureConfiguration
  private var accumulatedX = 0.0
  private var accumulatedY = 0.0
  private var axis: Axis?
  private var emittedSteps = 0
  private var consumingGesture = false
  private var swallowingMomentum = false
  private var wheelAccumulatedX = 0.0
  private var wheelAccumulatedY = 0.0

  init(configuration: ScrollGestureConfiguration) {
    self.configuration = configuration
  }

  /// The modifier the gesture requires; events without it pass through.
  var modifierBits: UInt64 { configuration.modifierBits }

  mutating func reset() {
    accumulatedX = 0
    accumulatedY = 0
    axis = nil
    emittedSteps = 0
    consumingGesture = false
    swallowingMomentum = false
    wheelAccumulatedX = 0
    wheelAccumulatedY = 0
  }

  mutating func handle(
    deltaX: Double,
    deltaY: Double,
    scrollPhase: Int64,
    momentumPhase: Int64,
    isContinuous: Bool,
    modifiersHeld: Bool
  ) -> Outcome {
    if momentumPhase != 0 {
      guard swallowingMomentum else { return .passThrough }
      if momentumPhase == Self.phaseEnded || momentumPhase == Self.phaseCancelled {
        swallowingMomentum = false
      }
      return .consume
    }

    if !isContinuous {
      return handleMouseWheel(
        deltaX: deltaX,
        deltaY: deltaY,
        scrollPhase: scrollPhase,
        modifiersHeld: modifiersHeld
      )
    }

    if consumingGesture {
      return consumeGesture(
        deltaX: deltaX,
        deltaY: deltaY,
        scrollPhase: scrollPhase
      )
    }

    guard modifiersHeld else { return .passThrough }

    switch scrollPhase {
    case Self.phaseBegan, Self.phaseChanged:
      beginGesture()
      return consumeGesture(
        deltaX: deltaX,
        deltaY: deltaY,
        scrollPhase: scrollPhase
      )
    default:
      return .passThrough
    }
  }

  private mutating func handleMouseWheel(
    deltaX: Double,
    deltaY: Double,
    scrollPhase: Int64,
    modifiersHeld: Bool
  ) -> Outcome {
    guard configuration.mouseWheel, modifiersHeld, !consumingGesture,
      scrollPhase == 0
    else {
      wheelAccumulatedX = 0
      wheelAccumulatedY = 0
      return .passThrough
    }
    wheelAccumulatedX += deltaX
    wheelAccumulatedY += deltaY
    guard let axis = wheelAxis() else { return .consume }
    let distance = axis == .horizontal ? wheelAccumulatedX : wheelAccumulatedY
    guard abs(distance) >= Self.wheelStep else { return .consume }
    // One notch may report several line units when accelerated. Run one step
    // per event so a fast spin cannot queue a burst of stale navigation.
    if axis == .horizontal { wheelAccumulatedX = 0 } else { wheelAccumulatedY = 0 }
    return .run(wheelCommand(axis: axis, forward: distance > 0))
  }

  private func wheelAxis() -> Axis? {
    let horizontal = abs(wheelAccumulatedX)
    let vertical = abs(wheelAccumulatedY)
    guard max(horizontal, vertical) >= Self.wheelStep else { return nil }
    return horizontal >= vertical ? .horizontal : .vertical
  }

  private mutating func beginGesture() {
    accumulatedX = 0
    accumulatedY = 0
    axis = nil
    emittedSteps = 0
    consumingGesture = true
    swallowingMomentum = false
  }

  private mutating func consumeGesture(
    deltaX: Double,
    deltaY: Double,
    scrollPhase: Int64
  ) -> Outcome {
    switch scrollPhase {
    case Self.phaseEnded, Self.phaseCancelled:
      consumingGesture = false
      swallowingMomentum = true
      accumulatedX = 0
      accumulatedY = 0
      axis = nil
      emittedSteps = 0
      return .consume
    case Self.phaseBegan, Self.phaseChanged:
      accumulatedX += deltaX
      accumulatedY += deltaY
      guard let axis = resolvedAxis() else { return .consume }
      let distance = axis == .horizontal ? accumulatedX : accumulatedY
      let steps = Int(abs(distance) / configuration.swipeThreshold)
      guard steps > emittedSteps else { return .consume }
      emittedSteps = steps
      return .run(swipeCommand(axis: axis, forward: distance > 0))
    default:
      return .consume
    }
  }

  private mutating func resolvedAxis() -> Axis? {
    if let axis { return axis }
    guard abs(accumulatedX) >= configuration.swipeThreshold
      || abs(accumulatedY) >= configuration.swipeThreshold
    else { return nil }
    let resolved: Axis = abs(accumulatedX) >= abs(accumulatedY) ? .horizontal : .vertical
    axis = resolved
    return resolved
  }

  private func swipeCommand(axis: Axis, forward: Bool) -> String {
    let forward = forward != configuration.invertDirection
    switch (axis, forward) {
    case (.horizontal, true): return "focus-column right"
    case (.horizontal, false): return "focus-column left"
    case (.vertical, true): return "focus-window-or-workspace up"
    case (.vertical, false): return "focus-window-or-workspace down"
    }
  }

  private func wheelCommand(axis: Axis, forward: Bool) -> String {
    let forward = forward != configuration.invertDirection
    switch (axis, forward) {
    case (.horizontal, true): return "focus-column right"
    case (.horizontal, false): return "focus-column left"
    case (.vertical, true): return "focus-window-or-workspace up"
    case (.vertical, false): return "focus-window-or-workspace down"
    }
  }

  private static let wheelStep = 1.0
  private static let phaseBegan: Int64 = 1
  private static let phaseChanged: Int64 = 2
  private static let phaseEnded: Int64 = 4
  private static let phaseCancelled: Int64 = 8
}
