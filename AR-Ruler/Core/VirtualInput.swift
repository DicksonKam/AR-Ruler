#if DEBUG
import AppKit

/// Debug builds only: scripted input for testing and screenshots without physical keys. It reaches the app
/// through the same `OverlayInput` entry point as real events, and synthesizes no system events.
enum VirtualInputCommand: Equatable {
    /// Nil means the keys configured in Preferences.
    case hold(NSEvent.ModifierFlags?)
    case release
    case shift(Bool)
    case move(CGPoint)
    case click(CGPoint)
    case drag(CGPoint, CGPoint)
    case rightClick(CGPoint)
    case esc
    case clear
    case wait(TimeInterval)
    case physical(Bool)
}

struct VirtualInputError: Error, Equatable {
    let number: Int
    let message: String
}

struct VirtualInputLine: Equatable {
    let number: Int
    let source: String
    let command: VirtualInputCommand
}

/// One command per line. Points are in screen points from the top-left of the main display, the same as
/// a screenshot, and may be written `x y` or `x,y`. `#` starts a comment.
enum VirtualInputScript {
    enum Parsed {
        case success([VirtualInputLine])
        case failure([VirtualInputError])
    }

    /// Either every line is good, or nothing runs and all the problems are reported.
    static func parse(_ text: String) -> Parsed {
        var lines: [VirtualInputLine] = []
        var errors: [VirtualInputError] = []
        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let source = (raw.components(separatedBy: "#").first ?? "").trimmingCharacters(in: .whitespaces)
            guard !source.isEmpty else { continue }
            let tokens = source.components(separatedBy: CharacterSet(charactersIn: " \t,")).filter { !$0.isEmpty }
            switch command(tokens) {
            case .success(let command):
                lines.append(VirtualInputLine(number: index + 1, source: source, command: command))
            case .failure(let error):
                errors.append(VirtualInputError(number: index + 1, message: "\(error.message): \(source)"))
            }
        }
        return errors.isEmpty ? .success(lines) : .failure(errors)
    }

    private static func command(_ tokens: [String]) -> Result<VirtualInputCommand, VirtualInputError> {
        let name = tokens[0].lowercased()
        let arguments = Array(tokens.dropFirst())
        func problem(_ message: String) -> Result<VirtualInputCommand, VirtualInputError> {
            .failure(VirtualInputError(number: 0, message: message))
        }
        func points(_ count: Int) -> [CGPoint]? {
            guard arguments.count == count * 2 else { return nil }
            let numbers = arguments.compactMap { Double($0) }
            guard numbers.count == arguments.count, numbers.allSatisfy({ $0.isFinite }) else { return nil }
            return stride(from: 0, to: numbers.count, by: 2).map { CGPoint(x: numbers[$0], y: numbers[$0 + 1]) }
        }
        func onOff() -> Bool? {
            guard arguments.count == 1 else { return nil }
            return ["on": true, "off": false][arguments[0].lowercased()]
        }
        switch name {
        case "hold":
            if arguments.isEmpty { return .success(.hold(nil)) }
            var flags: NSEvent.ModifierFlags = []
            for key in arguments {
                switch key.lowercased() {
                case "control": flags.insert(.control)
                case "option": flags.insert(.option)
                case "command": flags.insert(.command)
                default: return problem("hold takes control, option or command")
                }
            }
            return .success(.hold(flags))
        case "release":
            return arguments.isEmpty ? .success(.release) : problem("release takes nothing")
        case "shift":
            return onOff().map { .success(.shift($0)) } ?? problem("shift takes on or off")
        case "physical":
            return onOff().map { .success(.physical($0)) } ?? problem("physical takes on or off")
        case "move":
            return points(1).map { .success(.move($0[0])) } ?? problem("move takes x y")
        case "click":
            return points(1).map { .success(.click($0[0])) } ?? problem("click takes x y")
        case "rightclick":
            return points(1).map { .success(.rightClick($0[0])) } ?? problem("rightclick takes x y")
        case "drag":
            return points(2).map { .success(.drag($0[0], $0[1])) } ?? problem("drag takes x1 y1 x2 y2")
        case "esc":
            return arguments.isEmpty ? .success(.esc) : problem("esc takes nothing")
        case "clear":
            return arguments.isEmpty ? .success(.clear) : problem("clear takes nothing")
        case "wait":
            guard arguments.count == 1, let seconds = Double(arguments[0]), seconds >= 0, seconds.isFinite else {
                return problem("wait takes seconds")
            }
            return .success(.wait(seconds))
        default:
            return problem("unknown command")
        }
    }
}

/// What the runner drives: the app's controller, or a stand-in holding the same state in tests.
protocol VirtualInputTarget: AnyObject {
    /// Whether a mouse click here would really reach the overlay, rather than the app below.
    var capturesClicks: Bool { get }
    var configuredModifier: ModifierKey { get }
    /// The height of the main display, for turning top-left points into AppKit's y-up points.
    var mainDisplayHeight: CGFloat { get }
    var summary: String { get }
    func screen(at point: CGPoint) -> (frame: CGRect, pointsPerUnit: CGFloat)?
    func send(_ input: OverlayInput)
    func setPhysicalInputEnabled(_ enabled: Bool)
}

/// Plays commands in order, turning each into what the real source of that input would deliver.
final class VirtualInputRunner {
    private static let dragSteps = 8

    private let target: VirtualInputTarget
    private let log: (String) -> Void
    /// Waits, then continues. The app uses a timer, and tests continue straight away.
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var held: NSEvent.ModifierFlags = []
    private var shift = false
    private(set) var isRunning = false

    init(
        target: VirtualInputTarget,
        log: @escaping (String) -> Void,
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void
    ) {
        self.target = target
        self.log = log
        self.schedule = schedule
    }

    private var flags: NSEvent.ModifierFlags { shift ? held.union(.shift) : held }

    func run(script text: String, completion: (() -> Void)? = nil) {
        switch VirtualInputScript.parse(text) {
        case .failure(let errors):
            errors.forEach { log("error line \($0.number): \($0.message)") }
            log("nothing was run")
            completion?()
        case .success(let lines):
            isRunning = true
            play(lines[...], completion: completion)
        }
    }

    private func play(_ lines: ArraySlice<VirtualInputLine>, completion: (() -> Void)?) {
        guard let line = lines.first else {
            isRunning = false
            log("finished: \(target.summary)")
            completion?()
            return
        }
        let rest = lines.dropFirst()
        if case .wait(let seconds) = line.command {
            log("line \(line.number): \(line.source)")
            schedule(seconds) { [weak self] in self?.play(rest, completion: completion) }
            return
        }
        let note = apply(line.command)
        log("line \(line.number): \(line.source) -> \(note ?? target.summary)")
        play(rest, completion: completion)
    }

    private func appKitPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: target.mainDisplayHeight - point.y)
    }

    /// Returns a note when the command did something other than the plain thing.
    private func apply(_ command: VirtualInputCommand) -> String? {
        switch command {
        case .hold(let keys):
            held = keys ?? target.configuredModifier.flags
            target.send(.modifiers(flags, pointer: nil))
        case .release:
            held = []
            target.send(.modifiers(flags, pointer: nil))
        case .shift(let on):
            shift = on
            target.send(.modifiers(flags, pointer: nil))
        case .move(let point):
            target.send(.pointerMoved(appKitPoint(point)))
        case .click(let point):
            return press(at: appKitPoint(point), through: [])
        case .drag(let from, let to):
            let start = appKitPoint(from), end = appKitPoint(to)
            let path = (1...Self.dragSteps).map { step -> CGPoint in
                let t = CGFloat(step) / CGFloat(Self.dragSteps)
                return CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            }
            return press(at: start, through: path)
        case .rightClick(let point):
            let location = appKitPoint(point)
            target.send(.pointerMoved(location))
            guard target.capturesClicks else { return "passed through to the app below" }
            target.send(.clear)
        case .esc, .clear:
            target.send(.clear)
        case .physical(let on):
            target.setPhysicalInputEnabled(on)
        case .wait:
            break
        }
        return nil
    }

    private func press(at start: CGPoint, through path: [CGPoint]) -> String? {
        target.send(.pointerMoved(start))
        // The same gate as a real click: with the keys up, the overlay ignores the mouse.
        guard target.capturesClicks else { return "passed through to the app below" }
        guard let screen = target.screen(at: start) else { return "not on any screen" }
        target.send(.press(start, frame: screen.frame, pointsPerUnit: screen.pointsPerUnit))
        path.forEach { target.send(.drag($0, flags)) }
        target.send(.release(path.last ?? start, flags))
        return nil
    }
}
#endif
