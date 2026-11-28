import Foundation
import HelmRuntime

extension NamespacedStore {
    func readJSON<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        data(key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    func writeJSON<T: Encodable>(_ value: T, for key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        set(data, for: key)
    }
}
