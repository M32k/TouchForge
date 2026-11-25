import Foundation

/// config.json 읽기 + 변경 감시(저장하면 자동 반영)
final class ConfigStore {
    var onChange: (() -> Void)?

    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pendingReload: DispatchWorkItem?

    /// 설정 파일이 없으면 기본 설정을 만든다
    func ensureConfigExists() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: ConfigPaths.directory, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: ConfigPaths.file.path) {
            try DefaultConfig.json.write(to: ConfigPaths.file, atomically: true, encoding: .utf8)
            Log.info("기본 설정 파일 생성: \(ConfigPaths.file.path)")
        }
        let gifURL = ConfigPaths.directory.appendingPathComponent("sample.gif")
        if !fileManager.fileExists(atPath: gifURL.path), let gif = DefaultConfig.sampleGIF {
            try? gif.write(to: gifURL)
        }
    }

    func load() throws -> TouchForgeConfig {
        let data = try Data(contentsOf: ConfigPaths.file)
        return try JSONDecoder().decode(TouchForgeConfig.self, from: data)
    }

    /// 기본 설정으로 되돌린다 (기존 파일은 config.backup.json 으로 보관)
    func resetToDefault() throws {
        let fileManager = FileManager.default
        let backup = ConfigPaths.directory.appendingPathComponent("config.backup.json")
        if fileManager.fileExists(atPath: ConfigPaths.file.path) {
            if fileManager.fileExists(atPath: backup.path) { try fileManager.removeItem(at: backup) }
            try fileManager.moveItem(at: ConfigPaths.file, to: backup)
        }
        try DefaultConfig.json.write(to: ConfigPaths.file, atomically: true, encoding: .utf8)
    }

    // MARK: 변경 감시

    func startWatching() {
        watchDirectory()
        watchFile()
    }

    /// 폴더 감시: 에디터가 "새 파일로 바꿔치기" 저장하는 경우를 잡는다
    private func watchDirectory() {
        let descriptor = open(ConfigPaths.directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write], queue: .main)
        source.setEventHandler { [weak self] in
            self?.watchFile()
            self?.scheduleReload()
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        directorySource = source
    }

    /// 파일 감시: 같은 파일에 덮어쓰는 저장을 잡는다
    private func watchFile() {
        fileSource?.cancel()
        fileSource = nil
        let descriptor = open(ConfigPaths.file.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleReload()
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        fileSource = source
    }

    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.watchFile()
            self?.onChange?()
        }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
