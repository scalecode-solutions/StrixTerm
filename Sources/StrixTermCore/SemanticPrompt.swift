/// Semantic prompt state tracking for OSC 133 support.
///
/// This enables shell integration features like:
/// - Jumping between prompts
/// - Marking command output regions
/// - Command-level selection
///
/// See: https://gitlab.freedesktop.org/Per_Bothner/specifications/blob/master/proposals/semantic-prompts.md
public struct SemanticPromptState: Sendable {
    /// The current zone type (where we are in the prompt/command lifecycle).
    public var currentZone: PromptZone = .none

    /// The exit code from the last command (from OSC 133;D;exitcode).
    public var lastExitCode: Int?

    /// Whether we're currently inside a command output region.
    public var isInCommandOutput: Bool {
        currentZone == .commandExecuted
    }

    /// Whether we're currently at a prompt.
    public var isAtPrompt: Bool {
        currentZone == .promptStart
    }

    /// Process an OSC 133 sequence.
    public mutating func handleOSC133(_ command: Character, exitCode: Int? = nil) {
        switch command {
        case "A": currentZone = .promptStart
        case "B": currentZone = .commandStart
        case "C": currentZone = .commandExecuted
        case "D":
            currentZone = .commandFinished
            lastExitCode = exitCode
        default: break
        }
    }
}
