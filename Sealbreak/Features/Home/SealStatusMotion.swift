import Foundation

struct SealStatusMotion: Equatable {
    enum Phase: Equatable {
        case unknown
        case sealed
        case unsealed

        var isResolved: Bool {
            self != .unknown
        }
    }

    enum Effect: Equatable {
        case none
        case unsealReveal
        case result
    }

    struct AnimationID: Equatable {
        let generation: Int
        let effect: Effect
    }

    private(set) var phase: Phase
    private(set) var generation = 0
    private(set) var effect: Effect = .none
    private(set) var unsealRevealProgress: Double
    private(set) var resultScale = 1.0

    init(phase: Phase) {
        self.phase = phase
        unsealRevealProgress = phase == .unsealed ? 1 : 0
    }

    var animationID: AnimationID {
        AnimationID(
            generation: generation,
            effect: effect
        )
    }

    mutating func transition(to newPhase: Phase) {
        guard newPhase != phase else { return }

        let oldPhase = phase
        phase = newPhase
        generation += 1
        effect = .none
        resultScale = 1

        switch (oldPhase, newPhase) {
        case (_, .unknown):
            unsealRevealProgress = 0

        case (.unknown, .unsealed):
            unsealRevealProgress = 1

        case (.unknown, .sealed):
            unsealRevealProgress = 0

        case (.sealed, .unsealed):
            unsealRevealProgress = 0
            effect = .unsealReveal

        case (.unsealed, .sealed):
            unsealRevealProgress = 0
            effect = .result

        case (.sealed, .sealed), (.unsealed, .unsealed):
            break
        }
    }

    @discardableResult
    mutating func setUnsealRevealProgress(
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
    mutating func completeUnsealReveal(
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
    mutating func setResultScale(
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
