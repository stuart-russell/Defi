import CoreGraphics
import DefiConfig

/// A modifier plus a two-finger trackpad swipe that becomes existing navigation commands.
///
/// The gesture is opt-in and never steals a scroll the user did not reserve for
/// Defi: a continuous trackpad scroll is consumed only while the configured
/// modifier is held, and a mouse wheel is always left alone.
struct TrackpadSwipeGestureConfiguration: Equatable, Sendable {
  let modifierBits: UInt64
  let swipeThreshold: Double
  let invertDirection: Bool

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
  }
}

/// Accumulates one tracked scroll gesture and emits at most one command per
/// threshold step. Accumulating here keeps platform event handling thin and
/// lets the mapping be tested without Accessibility permission.
struct TrackpadSwipeGestureTracker {
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

  private let configuration: TrackpadSwipeGestureConfiguration
  private var accumulatedX = 0.0
  private var accumulatedY = 0.0
  private var axis: Axis?
  private var emittedSteps = 0
  private var consumingGesture = false
  private var swallowingMomentum = false

  init(configuration: TrackpadSwipeGestureConfiguration) {
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
  }

  /// `deltaX` and `deltaY` are the point deltas macOS reports for the gesture:
  /// positive moves right and down. Phases use the CoreGraphics scroll phase values.
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

    if consumingGesture {
      return consumeGesture(
        deltaX: deltaX,
        deltaY: deltaY,
        scrollPhase: scrollPhase
      )
    }

    guard isContinuous, modifiersHeld else { return .passThrough }

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
      return .run(command(axis: axis, distance: distance))
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

  private func command(axis: Axis, distance: Double) -> String {
    let forward = (distance > 0) != configuration.invertDirection
    switch (axis, forward) {
    case (.horizontal, true): return "focus-column right"
    case (.horizontal, false): return "focus-column left"
    case (.vertical, true): return "focus-window-or-workspace down"
    case (.vertical, false): return "focus-window-or-workspace up"
    }
  }

  private static let phaseBegan: Int64 = 1
  private static let phaseChanged: Int64 = 2
  private static let phaseEnded: Int64 = 4
  private static let phaseCancelled: Int64 = 8
}
