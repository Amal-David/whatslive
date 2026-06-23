import Foundation

func short(_ value: String, limit: Int = 80) -> String {
    guard value.count > limit else { return value }
    return String(value.prefix(max(0, limit - 1))) + "..."
}

func pathDisplay(_ path: String?) -> String {
    guard let path, !path.isEmpty else { return "cwd unavailable" }
    let home = NSHomeDirectory()
    if path.hasPrefix(home) {
        return "~" + path.dropFirst(home.count)
    }
    return path
}
