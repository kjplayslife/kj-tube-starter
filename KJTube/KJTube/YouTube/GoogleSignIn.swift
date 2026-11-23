import CryptoKit
import Foundation

/// The one-time Google sign-in for importing subscriptions (D152, D154). Pure link and request
/// building: the sign-in sheet itself is Apple's, opened from `ImportButton`.
/// Read-only YouTube access, with PKCE and no client secret (Google's flow for iPhone apps).
struct GoogleSignIn: Sendable {
    static let scope = "https://www.googleapis.com/auth/youtube.readonly"

    /// An "iOS" OAuth client ID from Google Cloud, like `123-abc.apps.googleusercontent.com`.
    let clientID: String
    /// Sent to Google and checked on the way back, so only our own sign-in is accepted.
    let state: String
    /// The PKCE secret: Google gets its hash now and the secret itself with the code.
    let verifier: String

    init(clientID: String, state: String = GoogleSignIn.randomToken(), verifier: String = GoogleSignIn.randomToken()) {
        self.clientID = clientID
        self.state = state
        self.verifier = verifier
    }

    enum Failure: Error, Equatable, Sendable {
        /// The person closed the sheet: no message (import spec).
        case cancelled
        /// Google said no (not a test user, access denied) or the answer made no sense.
        case denied
        case offline
    }

    /// Google sends the person back to the app on this scheme: the client ID, back to front.
    var callbackScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    var redirectURI: String { callbackScheme + ":/oauth2redirect" }

    var challenge: String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }

    /// Google's sign-in page, asking only to view the YouTube account.
    var signInURL: URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// The one-time code from the link Google sent the person back on.
    func code(from callback: URL) throws(Failure) -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("error") == nil, value("state") == state, let code = value("code"), !code.isEmpty else {
            throw .denied
        }
        return code
    }

    /// Swaps the one-time code for a short-lived access token.
    func tokenRequest(code: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
        ]
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        return request
    }

    static func accessToken(from data: Data) throws(Failure) -> String {
        struct Answer: Decodable { let access_token: String? }
        guard let token = (try? JSONDecoder().decode(Answer.self, from: data))?.access_token, !token.isEmpty else {
            throw .denied
        }
        return token
    }

    /// The access token for this sign-in. It is handed to the caller and kept nowhere (D154).
    func accessToken(callback: URL, session: URLSession = .shared) async throws(Failure) -> String {
        let request = tokenRequest(code: try code(from: callback))
        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            throw .offline
        }
        return try Self.accessToken(from: data)
    }

    static func randomToken() -> String {
        Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }).base64URLEncoded
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
