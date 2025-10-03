import Darwin
import Foundation
import OSLog
import Security

public enum DriverInstallerError: Error, CustomNSError, Equatable {
    case bundleNotFound
    case driverNotInstalled
    case authorizationFailed(OSStatus)
    case copyFailed(Int32)
    case removalFailed(Int32)
    case restartCoreAudioFailed(Int32)
    case verificationFailed
    case unknown(String)

    public static var errorDomain: String { "com.rokartur.Micmute.DriverInstaller" }

    public var errorCode: Int {
        switch self {
        case .bundleNotFound:
            return 1
        case .authorizationFailed(let status):
            return Int(status)
        case .copyFailed(let status), .removalFailed(let status), .restartCoreAudioFailed(let status):
            return Int(status)
        case .verificationFailed:
            return 2
        case .driverNotInstalled:
            return 3
        case .unknown:
            return -1
        }
    }

    public var errorUserInfo: [String: Any] {
        guard let description = errorDescription else {
            return [:]
        }
        return [NSLocalizedDescriptionKey: description]
    }
}

extension DriverInstallerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .bundleNotFound:
            return "Micmute couldn't find the bundled HAL audio plugin."
        case .authorizationFailed(let status):
            return "Administrator authorization failed (status \(status))."
        case .copyFailed(let status):
            return "Copying the driver into the HAL directory failed (status \(status))."
        case .removalFailed(let status):
            return "Removing the existing driver failed (status \(status))."
        case .restartCoreAudioFailed(let status):
            return "Failed to restart coreaudiod (status \(status))."
        case .verificationFailed:
            return "Micmute couldn't verify the HAL audio plugin after installation."
        case .driverNotInstalled:
            return "Micmute couldn't find the installed HAL audio plugin."
        case .unknown(let message):
            return message
        }
    }
}

struct DriverInstaller {
    static let driverBundleName = "PerAppVolumeDevice"

    private static let logger = Logger(subsystem: "com.rokartur.Micmute", category: "DriverInstaller")

    private struct PrivilegedCommand {
        let executablePath: String
        let arguments: [String]

        init(_ executablePath: String, arguments: [String], acceptableExitCodes: Set<Int32> = [0]) {
            self.executablePath = executablePath
            self.arguments = arguments
            // Note: acceptableExitCodes is kept for API compatibility but handled in shell script with 'set -e'
        }

        var debugDescription: String {
            ([executablePath] + arguments).map { component in
                component.contains(" ") ? "\"\(component)\"" : component
            }.joined(separator: " ")
        }
    }

    static func installDriverIfNeeded(forceInstall: Bool = false) throws {
        let needsInstall = forceInstall || !isDriverInstalled
        guard needsInstall else { return }

        do {
            // Proactively remove any legacy or renamed driver bundles before installing the new one.
            // This allows seamless migration if the bundle name changes in future versions.
            try removeLegacyDriverBundles()
            let exportedDriverURL = try exportBundledDriver()
            defer { try? FileManager.default.removeItem(at: exportedDriverURL.deletingLastPathComponent()) }

            try installDriverWithPrivileges(exportedDriverURL: exportedDriverURL, forceInstall: forceInstall)
            try verifyInstalledDriver()
        } catch let error as DriverInstallerError {
            // Surface bundle missing distinctly so callers can decide to continue in dev mode
            if case .bundleNotFound = error {
                logger.warning("Driver bundle not found in app resources; skipping privileged install step.")
            }
            throw error
        } catch {
            throw DriverInstallerError.unknown(error.localizedDescription)
        }
    }

    /// Potential historical / alternate names that might have been used for the driver.
    /// Extend this list as naming evolves to ensure only a single Micmute virtual device is present.
    private static var legacyBundleNames: [String] {
    // Current official name is PerAppVolumeDevice. List others if ever renamed.
        return [
            "VolumeControlDriver",
            "MicmuteVirtualDriver",
            "MicmuteAudioDriver"
        ]
    }

    /// Removes any legacy-named driver bundles that still exist to avoid duplicate virtual devices.
    private static func removeLegacyDriverBundles() throws {
        let halDir = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/HAL", isDirectory: true)
        for legacy in legacyBundleNames {
            // Skip if it matches the current canonical name
            if legacy == driverBundleName { continue }
            let candidate = halDir.appendingPathComponent("\(legacy).driver", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                logger.info("Removing legacy driver bundle at \(candidate.path, privacy: .public)")
                do {
                    try runPrivilegedCommands([
                        PrivilegedCommand("/bin/rm", arguments: ["-rf", candidate.path])
                    ])
                } catch {
                    // Non-fatal: surface as warning but continue install path
                    logger.warning("Failed to remove legacy driver \(legacy, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    static var driverDestinationURL: URL {
        URL(fileURLWithPath: "/Library/Audio/Plug-Ins/HAL/")
            .appendingPathComponent("\(driverBundleName).driver", isDirectory: true)
    }

    static var isDriverInstalled: Bool {
        FileManager.default.fileExists(atPath: driverDestinationURL.path)
    }

    @discardableResult
    static func uninstallDriver() throws -> Bool {
        guard FileManager.default.fileExists(atPath: driverDestinationURL.path) else {
            logger.info("Driver uninstall skipped – nothing at \(driverDestinationURL.path, privacy: .public)")
            return false
        }

        let sharedMemoryDirectory = "/Library/Application Support/Micmute"
        
        let commands: [PrivilegedCommand] = [
            PrivilegedCommand("/bin/rm", arguments: ["-rf", driverDestinationURL.path]),
            PrivilegedCommand("/bin/rm", arguments: ["-rf", sharedMemoryDirectory]),
            PrivilegedCommand("/usr/bin/killall", arguments: ["-9", "coreaudiod"], acceptableExitCodes: [0, 1])
        ]

        try runPrivilegedCommands(commands)
    logger.info("HAL audio plugin uninstalled from \(driverDestinationURL.path, privacy: .public)")
        return true
    }

    private static func exportBundledDriver() throws -> URL {
        guard let bundleURL = Bundle.main.url(forResource: driverBundleName, withExtension: "driver") else {
            throw DriverInstallerError.bundleNotFound
        }

        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: true)
            let destination = temporaryURL.appendingPathComponent("\(driverBundleName).driver", isDirectory: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: bundleURL, to: destination)
            return destination
        } catch {
            throw DriverInstallerError.unknown(error.localizedDescription)
        }
    }

    private static func installDriverWithPrivileges(exportedDriverURL: URL, forceInstall: Bool) throws {
        let commands = buildPrivilegedCommandSequence(exportedDriverURL: exportedDriverURL, forceInstall: forceInstall)
        let readableCommands = commands.map { $0.debugDescription }.joined(separator: " && ")
        logger.debug("Installing driver with privileged commands: \(readableCommands, privacy: .public)")
        try runPrivilegedCommands(commands)
    }

    private static func buildPrivilegedCommandSequence(exportedDriverURL: URL, forceInstall: Bool) -> [PrivilegedCommand] {
        let destinationPath = driverDestinationURL.path
        let sourcePath = exportedDriverURL.path
        let halDirectory = driverDestinationURL.deletingLastPathComponent().path
        let sharedMemoryDirectory = "/Library/Application Support/Micmute"

        var commands: [PrivilegedCommand] = [
            PrivilegedCommand("/bin/mkdir", arguments: ["-p", halDirectory]),
            PrivilegedCommand("/bin/mkdir", arguments: ["-p", sharedMemoryDirectory])
        ]

        if forceInstall || FileManager.default.fileExists(atPath: driverDestinationURL.path) {
            commands.append(PrivilegedCommand("/bin/rm", arguments: ["-rf", destinationPath]))
        }

        commands.append(PrivilegedCommand("/bin/cp", arguments: ["-R", sourcePath, destinationPath]))
        commands.append(PrivilegedCommand("/usr/sbin/chown", arguments: ["-R", "root:wheel", destinationPath]))
        commands.append(PrivilegedCommand("/bin/chmod", arguments: ["-R", "755", destinationPath]))
        
        // Set permissions for shared memory directory (world-writable but sticky bit)
        commands.append(PrivilegedCommand("/usr/sbin/chown", arguments: ["root:wheel", sharedMemoryDirectory]))
        commands.append(PrivilegedCommand("/bin/chmod", arguments: ["1777", sharedMemoryDirectory]))
        
        commands.append(PrivilegedCommand("/usr/bin/killall", arguments: ["-9", "coreaudiod"], acceptableExitCodes: [0, 1]))

        return commands
    }

    private static func runPrivilegedCommands(_ commands: [PrivilegedCommand]) throws {
        guard !commands.isEmpty else { return }

        // Build shell script - handle killall specially (it can return 1 if process not found)
        let scriptCommands = commands.enumerated().map { index, command -> String in
            let cmd = command.debugDescription
            // For killall, allow exit code 1 (process not found)
            if cmd.contains("/usr/bin/killall") {
                return "(\(cmd) || true)"
            }
            return cmd
        }.joined(separator: " && ")
        
        // Create a temporary script file
        let tempScriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sh")
        
        let scriptContent = """
        #!/bin/sh
        set -e
        \(scriptCommands)
        """
        
        try scriptContent.write(to: tempScriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempScriptURL) }
        
        // Make script executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScriptURL.path)
        
        logger.debug("Executing privileged script: \(tempScriptURL.path, privacy: .public)")
        
        // Use osascript to run with administrator privileges
        // This shows the native macOS authorization dialog
        let appleScript = """
        do shell script "\(tempScriptURL.path.replacingOccurrences(of: "\"", with: "\\\""))" with administrator privileges
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let exitCode = process.terminationStatus
            
            if exitCode != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                logger.error("Privileged script failed with exit code \(exitCode): \(errorOutput, privacy: .public)")
                
                // Check if user cancelled
                if errorOutput.contains("User canceled") || errorOutput.contains("-128") {
                    throw DriverInstallerError.authorizationFailed(errAuthorizationCanceled)
                }
                
                throw DriverInstallerError.copyFailed(exitCode)
            }
            
            logger.info("Privileged script executed successfully")
        } catch let error as DriverInstallerError {
            throw error
        } catch {
            logger.error("Failed to execute privileged script: \(error.localizedDescription, privacy: .public)")
            throw DriverInstallerError.unknown(error.localizedDescription)
        }
    }

    private static func verifyInstalledDriver() throws {
        guard FileManager.default.fileExists(atPath: driverDestinationURL.path) else {
            logger.error("Driver verification failed: destination path missing")
            throw DriverInstallerError.verificationFailed
        }

    logger.info("HAL audio plugin installed at \(driverDestinationURL.path, privacy: .public)")
    }
}
