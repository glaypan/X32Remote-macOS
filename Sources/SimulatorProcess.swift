import Foundation

/// 模拟器守护进程：拉起捆绑的 Python 跑 x32_simulator.py，
/// 负责选端口、收集日志、等待 /api/state 就绪、异常退出告警、退出时收尸。
final class SimulatorProcess {

    var onReady: ((Int) -> Void)?
    var onLogLine: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    private let configDir: URL
    private let logFileURL: URL
    private var process: Process?
    private var logHandle: FileHandle?
    private var logLines: [String] = []
    private let logQueue = DispatchQueue(label: "com.x32remote.simulator.log")
    private var isStopping = false
    private var readyPolls = 0

    private(set) var currentPort: Int?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        configDir = base.appendingPathComponent("X32Remote", isDirectory: true)
        logFileURL = configDir.appendingPathComponent("simulator.log")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    }

    var configDirectory: URL { configDir }
    var logFile: URL { logFileURL }

    // MARK: - 生命周期

    func start() {
        guard process == nil else { return }
        isStopping = false
        currentPort = nil
        ingest("=== 启动 \(Date()) ===\n")

        let fm = FileManager.default
        guard let python = bundledPythonURL() else {
            fail("找不到内置 Python 框架（安装包不完整）。")
            return
        }
        guard let script = Bundle.main.resourceURL?.appendingPathComponent("x32_simulator.py"),
              fm.fileExists(atPath: script.path) else {
            fail("找不到模拟器脚本 x32_simulator.py（安装包不完整）。")
            return
        }

        let port = pickPort()
        let configURL = configDir.appendingPathComponent("user_config.json")

        let p = Process()
        p.executableURL = python
        p.arguments = [script.path, "--config", configURL.path, "--web-port", String(port)]
        var env = ProcessInfo.processInfo.environment
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env
        p.currentDirectoryURL = configDir

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.ingest(text)
        }

        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self = self, !self.isStopping else { return }
                let code = Int(proc.terminationStatus)
                self.process = nil
                let detail = self.logTail(6)
                if detail.contains("绑定端口失败") {
                    self.fail("OSC/UDP 端口被占用——可能有另一个模拟器正在运行。\n\n\(detail)")
                } else if code == 0 {
                    self.fail("模拟器已退出。\n\n\(detail)")
                } else {
                    self.fail("模拟器异常退出（代码 \(code)）。\n\n\(detail)")
                }
            }
        }

        if !fm.fileExists(atPath: logFileURL.path) {
            fm.createFile(atPath: logFileURL.path, contents: nil)
        }
        logHandle = try? FileHandle(forWritingTo: logFileURL)

        do {
            try p.run()
            process = p
            readyPolls = 0
            pollUntilReady(port: port)
        } catch {
            fail("无法启动内置 Python：\(error.localizedDescription)")
        }
    }

    func stop() {
        isStopping = true
        guard let p = process else { return }
        if p.isRunning {
            p.terminate()
            let deadline = Date().addingTimeInterval(1.5)
            while p.isRunning && Date() < deadline {
                usleep(100_000)
            }
            if p.isRunning {
                kill(p.processIdentifier, SIGKILL)
            }
        }
        try? logHandle?.close()
        logHandle = nil
        process = nil
    }

    func restart() {
        stop()
        start()
    }

    func logTail(_ n: Int) -> String {
        logQueue.sync { logLines.suffix(n).joined(separator: "\n") }
    }

    // MARK: - 就绪探测

    private func pollUntilReady(port: Int) {
        readyPolls += 1
        guard readyPolls <= 80, process != nil, !isStopping else {
            if isStopping || process == nil { return }
            fail("模拟器启动超时：/api/state 20 秒无响应。\n\n\(logTail(10))")
            return
        }
        let url = URL(string: "http://127.0.0.1:\(port)/api/state")!
        let session = URLSession(configuration: .ephemeral, delegate: nil, delegateQueue: nil)
        session.dataTask(with: url) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self = self, self.process != nil, !self.isStopping else { return }
                let httpOK = (response as? HTTPURLResponse)?.statusCode == 200
                let jsonOK = httpOK && (data.flatMap { try? JSONSerialization.jsonObject(with: $0) }) != nil
                if jsonOK {
                    self.currentPort = port
                    self.onReady?(port)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.pollUntilReady(port: port)
                }
            }
        }.resume()
    }

    // MARK: - 端口选择

    /// 用户在控制台设置页保存过的网页端口优先；随后 8080、8081–8099 取第一个空闲。
    private func pickPort() -> Int {
        var candidates: [Int] = []
        if let saved = savedWebPort() { candidates.append(saved) }
        if !candidates.contains(8080) { candidates.append(8080) }
        candidates.append(contentsOf: 8081...8099)
        for p in candidates where p > 0 && isPortFree(p) {
            return p
        }
        return 8080
    }

    private func savedWebPort() -> Int? {
        let cfgURL = configDir.appendingPathComponent("user_config.json")
        guard let data = try? Data(contentsOf: cfgURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ports = obj["ports"] as? [String: Any],
              let web = ports["web"] as? Int, web > 0 else {
            return nil
        }
        return web
    }

    private func isPortFree(_ port: Int) -> Bool {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(truncatingIfNeeded: port)).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        return bind(fd, UnsafeRawPointer(&addr).assumingMemoryBound(to: sockaddr.self),
                    socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
    }

    // MARK: - Python 框架定位

    private func bundledPythonURL() -> URL? {
        guard let versions = Bundle.main.privateFrameworksURL?
                .appendingPathComponent("Python.framework", isDirectory: true)
                .appendingPathComponent("Versions", isDirectory: true) else { return nil }
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: versions.path) else { return nil }
        let numeric = entries
            .filter { $0.range(of: #"^\d+\.\d+$"#, options: .regularExpression) != nil }
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        guard let best = numeric.first else { return nil }
        let python = versions.appendingPathComponent(best).appendingPathComponent("bin/python3")
        return FileManager.default.fileExists(atPath: python.path) ? python : nil
    }

    // MARK: - 日志

    private func ingest(_ text: String) {
        logQueue.async { [weak self] in
            guard let self = self else { return }
            self.logLines.append(text)
            if self.logLines.count > 500 { self.logLines.removeFirst(250) }
            self.logHandle?.seekToEndOfFile()
            self.logHandle?.write(text.data(using: .utf8) ?? Data())
        }
        let lines = text.split(separator: "\n").map(String.init)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for line in lines where !line.isEmpty {
                self.onLogLine?(line)
            }
        }
    }

    private func fail(_ message: String) {
        stop()
        onFailure?(message)
    }
}
