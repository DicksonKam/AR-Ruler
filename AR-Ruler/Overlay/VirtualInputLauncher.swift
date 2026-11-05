#if DEBUG
import Foundation

/// Runs `--input-script <path>` at launch, then runs it again whenever the file changes, so an open app can be
/// given new input by rewriting the file. Real input is off for this run, so it can't disturb what's being
/// captured, until a script says `physical on`. Each run's log goes to `<path>.log`.
final class VirtualInputLauncher {
    private static let argument = "--input-script"

    private let path: String
    private let logPath: String
    private let runner: VirtualInputRunner
    private var lastModified: Date?
    private var watcher: Timer?

    init?(target: VirtualInputTarget, arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let index = arguments.firstIndex(of: Self.argument), index + 1 < arguments.count else { return nil }
        let path = arguments[index + 1]
        let logPath = path + ".log"
        self.path = path
        self.logPath = logPath
        runner = VirtualInputRunner(
            target: target,
            log: { line in
                NSLog("VirtualInput: %@", line)
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(Data((line + "\n").utf8))
                    handle.closeFile()
                }
            },
            schedule: { seconds, next in
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: next)
            }
        )
        target.setPhysicalInputEnabled(false)
        runIfChanged()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.runIfChanged() }
        RunLoop.main.add(timer, forMode: .common)
        watcher = timer
    }

    private func runIfChanged() {
        guard !runner.isRunning else { return }
        let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        guard modified != lastModified || lastModified == nil else { return }
        lastModified = modified
        FileManager.default.createFile(atPath: logPath, contents: nil)
        guard let script = try? String(contentsOfFile: path, encoding: .utf8) else {
            // Stays in the log once, rather than repeating every half second.
            lastModified = modified ?? .distantPast
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.write(Data("error: can't read \(path)\n".utf8))
                handle.closeFile()
            }
            return
        }
        runner.run(script: script)
    }
}
#endif
