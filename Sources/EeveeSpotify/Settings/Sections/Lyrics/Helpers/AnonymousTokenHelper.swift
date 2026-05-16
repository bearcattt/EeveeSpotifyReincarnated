import UIKit
import Combine

struct AnonymousTokenHelper {
    private static let endpoints = [
        "https://apic-desktop.musixmatch.com/ws/1.1/token.get?app_id=web-desktop-app-v1.0",
        "https://apic.musixmatch.com/ws/1.1/token.get?app_id=\(UIDevice.current.musixmatchAppId)"
    ]

    static func requestAnonymousMusixmatchToken() -> AnyPublisher<String, Error> {
        Future<String, Error> { promise in
            Task {
                var lastError: Error = AnonymousTokenError.invalidResponse

                for endpoint in endpoints {
                    guard let url = URL(string: endpoint) else { continue }

                    var request = URLRequest(url: url)
                    request.timeoutInterval = 15
                    request.setValue(
                        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                        forHTTPHeaderField: "User-Agent"
                    )
                    request.setValue("application/json", forHTTPHeaderField: "Accept")

                    do {
                        let (data, response) = try await URLSession.shared.data(for: request)

                        // Log raw response for debugging
                        let rawString = String(data: data, encoding: .utf8) ?? "non-utf8"
                        NSLog("[EeveeSpotify] AnonymousToken raw response (\(endpoint)): \(rawString.prefix(300))")

                        if let http = response as? HTTPURLResponse {
                            NSLog("[EeveeSpotify] AnonymousToken HTTP status: \(http.statusCode)")
                            guard http.statusCode == 200 else { continue }
                        }

                        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            NSLog("[EeveeSpotify] AnonymousToken: failed to parse JSON")
                            continue
                        }

                        guard let message = json["message"] as? [String: Any] else {
                            NSLog("[EeveeSpotify] AnonymousToken: no 'message' key")
                            continue
                        }

                        // body can be [] (array) when rate-limited — guard against that
                        guard let body = message["body"] as? [String: Any] else {
                            NSLog("[EeveeSpotify] AnonymousToken: body is not a dict (likely rate-limited)")
                            continue
                        }

                        guard let userToken = body["user_token"] as? String,
                              !userToken.isEmpty,
                              userToken != "UpgradeRequired" else {
                            NSLog("[EeveeSpotify] AnonymousToken: invalid user_token value")
                            continue
                        }

                        NSLog("[EeveeSpotify] AnonymousToken: success, token length \(userToken.count)")
                        promise(.success(userToken))
                        return

                    } catch {
                        NSLog("[EeveeSpotify] AnonymousToken: request error: \(error)")
                        lastError = error
                        continue
                    }
                }

                promise(.failure(lastError))
            }
        }
        .eraseToAnyPublisher()
    }
}
