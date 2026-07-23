// HTTP.swift — the bounded URLSession every provider call uses.

import Foundation

extension URLSession {
    /// Bounded session for all provider/auth requests.
    ///
    /// WHY THIS EXISTS: `URLSession.shared` has a `timeoutIntervalForResource`
    /// of SEVEN DAYS. A request that stalls — classically, one in flight
    /// when the Mac goes to sleep — therefore never returns, so
    /// `await session.data(...)` hangs forever. That wedged the refresh
    /// loop: `isRefreshing` stuck true, single-flight guard blocking every
    /// later refresh, spinner spinning, "updated 5h ago". These bounds
    /// guarantee every request completes or fails within ~45s, so a
    /// refresh can never hang the loop.
    static let robut: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15   // idle gap between packets
        config.timeoutIntervalForResource = 45  // hard cap on the whole load
        config.waitsForConnectivity = false     // fail fast; the loop retries
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
}
