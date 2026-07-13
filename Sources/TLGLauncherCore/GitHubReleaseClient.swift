import Foundation

public protocol ReleaseFetching: Sendable {
    /// Most recent releases, newest first as returned by the GitHub API.
    func fetchReleases(count: Int) async throws -> [GameRelease]
}

public enum ReleaseClientError: Error, CustomStringConvertible {
    case httpStatus(Int)
    public var description: String {
        switch self {
        case .httpStatus(let code):
            return "GitHub returned HTTP \(code). If this persists you may be rate-limited; try again later."
        }
    }
}

public struct GitHubReleaseClient: ReleaseFetching {
    public let repository: String
    private let session: URLSession

    public init(repository: String = "Cataclysm-TLG/Cataclysm-TLG", session: URLSession = .shared) {
        self.repository = repository
        self.session = session
    }

    public func fetchReleases(count: Int = 30) async throws -> [GameRelease] {
        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=\(count)")!
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("tlg-launcher", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ReleaseClientError.httpStatus(http.statusCode)
        }
        return try Self.parseReleases(data)
    }

    public static func parseReleases(_ data: Data) throws -> [GameRelease] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([GameRelease].self, from: data)
    }
}
