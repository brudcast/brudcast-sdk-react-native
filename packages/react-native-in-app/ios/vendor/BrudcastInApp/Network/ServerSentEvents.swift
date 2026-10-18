import Foundation
import Brudcast

struct ServerSentEvent: Equatable {
    var event: String
    var data: String
}

/// Splits a server-sent event stream into events, fed one chunk of bytes at a time.
struct ServerSentEventParser {
    private var buffer = Data()
    private var eventName = ""
    private var dataLines: [String] = []
    private(set) var retryMilliseconds: Int?

    /// Feeds bytes from the stream.
    ///
    /// - Parameter chunk: The bytes received.
    /// - Returns: The events completed by these bytes.
    mutating func feed(_ chunk: Data) -> [ServerSentEvent] {
        buffer.append(chunk)
        var events: [ServerSentEvent] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var lineData = buffer[buffer.startIndex..<newline]
            if lineData.last == 0x0D {
                lineData = lineData.dropLast()
            }
            buffer.removeSubrange(buffer.startIndex...newline)
            let line = String(decoding: lineData, as: UTF8.self)
            if let event = consume(line) {
                events.append(event)
            }
        }
        return events
    }

    private mutating func consume(_ line: String) -> ServerSentEvent? {
        if line.isEmpty {
            defer {
                eventName = ""
                dataLines = []
            }
            guard !dataLines.isEmpty || !eventName.isEmpty else { return nil }
            return ServerSentEvent(event: eventName.isEmpty ? "message" : eventName, data: dataLines.joined(separator: "\n"))
        }
        if line.hasPrefix(":") {
            return nil
        }
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[line.startIndex..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") {
                value = value.dropFirst()
            }
        } else {
            field = Substring(line)
            value = ""
        }
        switch field {
        case "event":
            eventName = String(value)
        case "data":
            dataLines.append(String(value))
        case "retry":
            retryMilliseconds = Int(value)
        default:
            break
        }
        return nil
    }
}

/// Holds the `/stream` connection open while the app is in the foreground.
final class StreamClient: NSObject, URLSessionDataDelegate {
    private let queue: DispatchQueue
    private let onEvent: (ServerSentEvent) -> Void
    private let onUnauthorized: () -> Void
    private var urlSession: URLSession?
    private var task: URLSessionDataTask?
    private var parser = ServerSentEventParser()
    private var failures = 0
    private var reconnect: DispatchWorkItem?
    private var wanted = false
    private var tokenProvider: (() -> (URL, String)?)?

    init(queue: DispatchQueue, onEvent: @escaping (ServerSentEvent) -> Void, onUnauthorized: @escaping () -> Void) {
        self.queue = queue
        self.onEvent = onEvent
        self.onUnauthorized = onUnauthorized
    }

    /// Opens the stream, and keeps reopening it after drops until `stop`.
    ///
    /// - Parameter endpoint: Returns the stream URL and the session token, or nil when no session
    ///   is open.
    func start(endpoint: @escaping () -> (URL, String)?) {
        tokenProvider = endpoint
        wanted = true
        guard task == nil else { return }
        connect()
    }

    func stop() {
        wanted = false
        reconnect?.cancel()
        task?.cancel()
        task = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    /// Drops the current connection and opens a new one, such as after a session refresh.
    func restart() {
        guard wanted else { return }
        task?.cancel()
        task = nil
        connect()
    }

    private func connect() {
        guard wanted, let (url, token) = tokenProvider?() else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 90
        if urlSession == nil {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 90
            configuration.timeoutIntervalForResource = 24 * 3_600
            let delegateQueue = OperationQueue()
            delegateQueue.underlyingQueue = queue
            delegateQueue.maxConcurrentOperationCount = 1
            urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
        }
        parser = ServerSentEventParser()
        let created = urlSession?.dataTask(with: request)
        task = created
        created?.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 200 {
            failures = 0
            completionHandler(.allow)
            return
        }
        completionHandler(.cancel)
        if status == 401 {
            onUnauthorized()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard dataTask == task else { return }
        for event in parser.feed(data) {
            onEvent(event)
        }
    }

    func urlSession(_ session: URLSession, task finished: URLSessionTask, didCompleteWithError error: Error?) {
        guard finished == task else { return }
        task = nil
        guard wanted else { return }
        failures += 1
        let base = Double(parser.retryMilliseconds ?? 5_000) / 1_000
        let delay = min(60, base * pow(2, Double(max(0, failures - 1))))
        BrudcastLogger.shared.debug("Stream closed\(error.map { ": \($0.localizedDescription)" } ?? ""); reconnecting in \(Int(delay))s")
        let work = DispatchWorkItem { [weak self] in self?.connect() }
        reconnect = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
