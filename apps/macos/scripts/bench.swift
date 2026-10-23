import AppKit

// 起動時間、打鍵のCPU時間、メモリを計測
// 使い方: bench <Plainsong.app> [比較対象.app ...]

let launchRuns = 20
let typingRuns = 5
let bulkLines = 5000
let keystrokes = 300
let bulkLine = "あいうえおかきくけこさしすせそたちつて\n"

struct LaunchResult {
    var total: Double
    var process: Double
    var memory: Double
}

struct TypingResult {
    var emptyKey: Double
    var bulk: Double
    var fullKey: Double
    var memory: Double
    var characters: Double
}

let timebase: mach_timebase_info_data_t = {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return info
}()

func wallMs() -> Double {
    Date().timeIntervalSince1970 * 1000
}

func processStartMs(_ pid: pid_t) -> Double {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    sysctl(&mib, 4, &info, &size, nil, 0)
    let start = info.kp_proc.p_un.__p_starttime
    return Double(start.tv_sec) * 1000 + Double(start.tv_usec) / 1000
}

func resourceUsage(_ pid: pid_t) -> rusage_info_v4 {
    var info = rusage_info_v4()
    _ = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    return info
}

func cpuMs(_ pid: pid_t) -> Double {
    let usage = resourceUsage(pid)
    return Double(usage.ri_user_time + usage.ri_system_time) * Double(timebase.numer) / Double(timebase.denom) / 1e6
}

func footprintMB(_ pid: pid_t) -> Double {
    Double(resourceUsage(pid).ri_phys_footprint) / 1_048_576
}

func hasWindow(_ pid: pid_t) -> Bool {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains {
        ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
    }
}

/// 保存した内容が残っていると次の起動で復元されてしまうので、起動のたびに置き直す
/// 本番のPlainsongで書いた内容を消さないよう、bundle IDが.benchで終わるアプリのものだけを扱う
func savedDataDirectory(_ url: URL) -> URL? {
    guard let identifier = Bundle(url: url)?.bundleIdentifier, identifier.hasSuffix(".bench") else { return nil }
    return FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Containers/\(identifier)/Data/Library/Application Support/\(identifier)")
}

func resetSavedData(_ url: URL, text: String?) throws {
    guard let directory = savedDataDirectory(url) else { return }
    try? FileManager.default.removeItem(at: directory)
    if let text {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: directory.appending(path: "text.txt"))
    }
}

func launch(_ url: URL, restoring text: String? = nil) async throws -> NSRunningApplication {
    try resetSavedData(url, text: text)
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    return try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
}

func waitForWindow(_ pid: pid_t, since start: Double) -> Bool {
    while !hasWindow(pid) {
        if wallMs() - start > 5000 {
            FileHandle.standardError.write(Data("ウィンドウが出ませんでした。画面がロックされていないか確かめてください\n".utf8))
            return false
        }
        usleep(250)
    }
    return true
}

func quit(_ pid: pid_t) {
    kill(pid, SIGKILL)
    usleep(400_000)
}

func measureLaunch(_ url: URL, restoring text: String? = nil) async throws -> LaunchResult? {
    let start = wallMs()
    let pid = try await launch(url, restoring: text).processIdentifier
    let processStart = processStartMs(pid)
    defer { quit(pid) }
    guard waitForWindow(pid, since: start) else { return nil }
    let shown = wallMs()
    usleep(1_500_000)
    return LaunchResult(total: shown - start, process: shown - processStart, memory: footprintMB(pid))
}

func type(_ text: String, to pid: pid_t) {
    let characters = Array(text.utf16)
    for keyDown in [true, false] {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: keyDown) else { continue }
        event.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: characters)
        event.postToPid(pid)
    }
}

func waitUntilIdle(_ pid: pid_t) -> Double {
    var last = cpuMs(pid)
    var lastChange = wallMs()
    while wallMs() - lastChange < 500 {
        usleep(50000)
        let current = cpuMs(pid)
        if current - last > 1 {
            last = current
            lastChange = wallMs()
        }
    }
    return lastChange
}

func keyCost(_ pid: pid_t) -> Double {
    _ = waitUntilIdle(pid)
    let before = cpuMs(pid)
    for index in 0 ..< keystrokes {
        type(index % 40 == 39 ? "\n" : "a", to: pid)
        usleep(8000)
    }
    _ = waitUntilIdle(pid)
    return (cpuMs(pid) - before) / Double(keystrokes)
}

/// 入力がすべて届いたかを確かめるため、フォーカスのある要素の文字数を読む
func characterCount(_ pid: pid_t) -> Double {
    var focused: CFTypeRef?
    AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &focused)
    guard let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return -1 }
    var count: CFTypeRef?
    let element = unsafeBitCast(focused, to: AXUIElement.self)
    AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &count)
    return (count as? NSNumber)?.doubleValue ?? -1
}

func measureTyping(_ url: URL) async throws -> TypingResult? {
    let app = try await launch(url)
    let pid = app.processIdentifier
    defer { quit(pid) }
    guard waitForWindow(pid, since: wallMs()) else { return nil }
    app.activate()
    usleep(500_000)

    let emptyKey = keyCost(pid)
    let start = wallMs()
    for _ in 0 ..< bulkLines {
        type(bulkLine, to: pid)
    }
    let bulk = waitUntilIdle(pid) - start
    let fullKey = keyCost(pid)
    return TypingResult(
        emptyKey: emptyKey,
        bulk: bulk,
        fullKey: fullKey,
        memory: footprintMB(pid),
        characters: characterCount(pid)
    )
}

func median(_ values: [Double], format: String = "%.2f") -> String {
    guard !values.isEmpty else { return "-" }
    return String(format: format, values.sorted()[values.count / 2])
}

let paths = Array(CommandLine.arguments.dropFirst())
guard !paths.isEmpty else {
    print("使い方: bench <Plainsong.app> [比べたい.app ...]")
    exit(64)
}

guard AXIsProcessTrusted() else {
    print("キー入力を送るため、このターミナルにアクセシビリティの権限を与えてください")
    exit(1)
}

let apps = paths.map { URL(fileURLWithPath: $0) }
guard apps.allSatisfy({ savedDataDirectory($0) != nil }) else {
    print("保存した内容を消しながら測るので、mise run macos:benchでビルドした、bundle IDが.benchで終わるアプリだけを渡してください")
    exit(64)
}

let restoredText = String(repeating: bulkLine, count: bulkLines)

do {
    // 1回目はサンドボックスのコンテナ作成などを含むので捨てる
    for url in apps {
        _ = try await measureLaunch(url)
    }
    // 時間帯による偏りが出ないよう、アプリを交互に起動する
    var launches = Array(repeating: [LaunchResult](), count: apps.count)
    var restoredLaunches = launches
    for _ in 0 ..< launchRuns {
        for (index, url) in apps.enumerated() {
            if let result = try await measureLaunch(url) {
                launches[index].append(result)
            }
        }
    }
    for _ in 0 ..< launchRuns {
        for (index, url) in apps.enumerated() {
            if let result = try await measureLaunch(url, restoring: restoredText) {
                restoredLaunches[index].append(result)
            }
        }
    }
    var typings = Array(repeating: [TypingResult](), count: apps.count)
    for _ in 0 ..< typingRuns {
        for (index, url) in apps.enumerated() {
            if let result = try await measureTyping(url) {
                typings[index].append(result)
            }
        }
    }

    for (index, path) in paths.enumerated() {
        let launch = launches[index]
        let restoredLaunch = restoredLaunches[index]
        let typing = typings[index]
        print(path)
        print("  起動まで（ms）           Launch Servicesから \(median(launch.map(\.total)))")
        print("                           プロセス開始から \(median(launch.map(\.process)))")
        print("  起動直後のメモリ（MB）   \(median(launch.map(\.memory)))")
        print("  10万字を復元しての起動   プロセス開始から（ms） \(median(restoredLaunch.map(\.process)))")
        print("                           起動直後のメモリ（MB） \(median(restoredLaunch.map(\.memory)))")
        print("  1打鍵のCPU（ms）         空のとき \(median(typing.map(\.emptyKey)))")
        print("                           10万字のとき \(median(typing.map(\.fullKey)))")
        print("  10万字の入力（ms）       \(median(typing.map(\.bulk)))")
        print("  入力後のメモリ（MB）     \(median(typing.map(\.memory)))")
        print("  入力後の文字数           \(median(typing.map(\.characters), format: "%.0f"))")
    }
} catch {
    print(error)
    exit(1)
}
