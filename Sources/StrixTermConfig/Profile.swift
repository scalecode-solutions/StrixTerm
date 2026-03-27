import Foundation

/// A terminal profile bundles appearance and behavior settings.
/// Addresses issue #442 (Mac Terminal App Feature List) for profile support.
public struct Profile: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var configuration: TerminalConfiguration
    public var appearance: AppearanceSettings
    public var shell: ShellSettings

    public init(
        id: UUID = UUID(),
        name: String = "Default",
        configuration: TerminalConfiguration = .default,
        appearance: AppearanceSettings = .default,
        shell: ShellSettings = .default
    ) {
        self.id = id
        self.name = name
        self.configuration = configuration
        self.appearance = appearance
        self.shell = shell
    }

    public static let `default` = Profile()
}

/// Visual appearance settings for a terminal session.
public struct AppearanceSettings: Codable, Sendable {
    public var fontFamily: String
    public var fontSize: Double
    public var colorPalette: String
    public var cursorStyle: String
    public var blinkEnabled: Bool
    public var opacity: Double
    public var lineSpacing: Double
    public var letterSpacing: Double

    public init(
        fontFamily: String = "SF Mono",
        fontSize: Double = 13,
        colorPalette: String = "xterm",
        cursorStyle: String = "blinkBlock",
        blinkEnabled: Bool = true,
        opacity: Double = 1.0,
        lineSpacing: Double = 1.0,
        letterSpacing: Double = 0
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.colorPalette = colorPalette
        self.cursorStyle = cursorStyle
        self.blinkEnabled = blinkEnabled
        self.opacity = opacity
        self.lineSpacing = lineSpacing
        self.letterSpacing = letterSpacing
    }

    public static let `default` = AppearanceSettings()
}

/// Shell and process settings.
public struct ShellSettings: Codable, Sendable {
    public var command: String
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectory: String?
    public var loginShell: Bool

    public init(
        command: String = "/bin/zsh",
        arguments: [String] = ["--login"],
        environment: [String: String] = [:],
        workingDirectory: String? = nil,
        loginShell: Bool = true
    ) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.loginShell = loginShell
    }

    public static let `default` = ShellSettings()
}
