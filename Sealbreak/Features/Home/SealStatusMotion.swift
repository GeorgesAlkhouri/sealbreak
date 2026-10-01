import Foundation

package struct SealStatusMotion: Equatable {
    package enum Phase: Equatable {
        case unknown
        case sealed
        case unsealed

        package var isResolved: Bool {
            self != .unknown
        }
    }

    package enum Effect: Equatable {
        case none
        case unsealReveal
        case result
    }

    package struct AnimationID: Equatable {
        package let generation: Int
        package let effect: Effect
    }

    private(set) var phase: Phase
    private(set) var generation = 0
    private(set) var effect: Effect = .none
    package private(set) var unsealRevealProgress: Double
    package private(set) var resultScale = 1.0

    package init(phase: Phase) {
        self.phase = phase
        unsealRevealProgress = phase == .unsealed ? 1 : 0
    }

    package var animationID: AnimationID {
        AnimationID(
            generation: generation,
            effect: effect
        )
    }

    package mutating func transition(to newPhase: Phase) {
        guard newPhase != phase else { return }

        let oldPhase = phase
        phase = newPhase
        generation += 1
        effect = .none
        resultScale = 1

        switch newPhase {
        case .unknown:
            unsealRevealProgress = 0

        case .sealed:
            unsealRevealProgress = 0
            if oldPhase == .unsealed {
                effect = .result
            }

        case .unsealed:
            if oldPhase == .unknown {
                unsealRevealProgress = 1
            } else {
                unsealRevealProgress = 0
                effect = .unsealReveal
            }
        }
    }

    @discardableResult
    package mutating func setUnsealRevealProgress(
        _ progress: Double,
        for animationID: AnimationID
    ) -> Bool {
        guard animationID == self.animationID,
              phase == .unsealed,
              effect == .unsealReveal
        else {
            return false
        }

        unsealRevealProgress = min(1, max(0, progress))
        return true
    }

    @discardableResult
    package mutating func completeUnsealReveal(
        for animationID: AnimationID
    ) -> Bool {
        guard animationID == self.animationID,
              phase == .unsealed,
              effect == .unsealReveal
        else {
            return false
        }

        effect = .result
        return true
    }

    @discardableResult
    package mutating func setResultScale(
        _ scale: Double,
        for animationID: AnimationID
    ) -> Bool {
        guard animationID == self.animationID,
              phase.isResolved,
              effect == .result
        else {
            return false
        }

        resultScale = scale
        return true
    }
}
