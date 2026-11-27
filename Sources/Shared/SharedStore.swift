import Foundation

/// TouchForge 앱 ↔ 바탕화면 위젯이 같이 보는 구독 한도 파일
/// ~/Library/Application Support/TouchForge/usage.json
/// (위젯은 샌드박스라서 이 폴더만 읽기 전용으로 열어 둠)
enum SharedStore {
    /// 샌드박스 안에서도 실제 홈 폴더를 얻기 위해 passwd 에서 직접 읽는다
    static var realHome: String {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    static var directory: URL {
        URL(fileURLWithPath: realHome)
            .appendingPathComponent("Library/Application Support/TouchForge", isDirectory: true)
    }

    static var fileURL: URL {
        directory.appendingPathComponent("usage.json")
    }

    static func save(_ bundle: SnapshotBundle) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(bundle)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[TouchForge] 저장 실패: %@", error.localizedDescription)
        }
    }

    static func load() -> SnapshotBundle? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(SnapshotBundle.self, from: data)
    }
}
