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
                for endpoint in endpoints {
                    guard let url = URL(string: endpoint) else { continue }

                    var request = URLRequest(url: url)
                    request.timeoutInterval = 10
                    request.setValue(
                        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                        forHTTPHeaderField: "User-Agent"
                    )

                    do {
                        let (data, response) = try await URLSession.shared.data(for: request)

                        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                            continue
                        }

                        guard
                            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                            let message = json["message"] as? [String: Any],
                            let body = message["body"] as? [String: Any],
                            let userToken = body["user_token"] as? String,
                            !userToken.isEmpty,
                            userToken != "UpgradeRequired"
                        else {
                            continue
                        }

                        promise(.success(userToken))
                        return
                    } catch {
                        continue
                    }
                }

                promise(.failure(AnonymousTokenError.invalidResponse))
            }
        }
        .eraseToAnyPublisher()
    }
}
