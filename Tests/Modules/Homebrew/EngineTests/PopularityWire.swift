import Foundation
@testable import Module_Homebrew_Engine

/// One side of the boundary `FilePopularityStore` stands on: a transfer that
/// answers, and a record of what it was asked.
///
/// It stands for the wire and for nothing else — the store's own clock, files
/// and readings are the real ones in every test that uses this, which is the
/// point: what these tests are about is what the store does with an answer, and
/// a fake that also decided that would be testing itself.
///
/// `HTTPURLResponse` rather than a status of its own, because that is what
/// `URLSession` hands over for an `https` request and the store's own glue is
/// the only place the distinction exists.
final class PopularityWire: @unchecked Sendable {
    /// What to answer, by request. Throwing stands for the whole family of
    /// transport failures — no network, a refused connection, a deadline, and
    /// the cancellation that arrives at quit.
    typealias Reply = @Sendable (URLRequest) throws -> (status: Int, body: Data,
                                                        headers: [String: String])

    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private let reply: Reply

    init(reply: @escaping Reply) { self.reply = reply }

    /// Answers every ask the same way, with an ETag on it.
    convenience init(status: Int, body: Data, etag: String = "\"v1\"") {
        self.init { _ in (status, body, ["ETag": etag]) }
    }

    /// Answers nothing at all, the way a Mac with no network does.
    static func offline() -> PopularityWire {
        PopularityWire { _ in throw URLError(.notConnectedToInternet) }
    }

    var asked: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    private func record(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
    }

    var transfer: FilePopularityStore.Transfer {
        { [self] request in
            record(request)
            let (status, body, headers) = try reply(request)
            let http = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: headers)!
            return (body, http)
        }
    }
}

/// A document in the shape Homebrew publishes, with the counts asked for.
func countsDocument(_ counts: [String: Int]) -> Data {
    let entries = counts.map { "\"\($0.key)\":[{\"count\":\"\($0.value)\"}]" }.joined(separator: ",")
    return Data("{\"formulae\":{\(entries)}}".utf8)
}
