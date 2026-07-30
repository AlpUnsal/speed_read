import Foundation

/// Fetched X/Twitter post content, normalized across API providers.
struct FetchedTweet {
    let text: String
    let authorName: String
    let authorHandle: String
}

/// Resolves X/Twitter status URLs to their full post text.
///
/// x.com serves a JavaScript-only shell to plain HTTP fetches, so post text
/// (including 25,000-character long-form posts, which embed/oEmbed endpoints
/// truncate) is fetched through the FxTwitter API, with vxTwitter as fallback.
enum TweetFetcher {

    /// Extracts the numeric status ID if the URL points at an X/Twitter post.
    static func statusID(from url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let tweetHosts: Set<String> = [
            "x.com", "www.x.com", "mobile.x.com",
            "twitter.com", "www.twitter.com", "mobile.twitter.com"
        ]
        guard tweetHosts.contains(host) else { return nil }

        // Matches /<user>/status/<id>, /i/status/<id>, /i/web/status/<id>
        guard let range = url.path.range(of: "/status(?:es)?/([0-9]+)", options: .regularExpression) else {
            return nil
        }
        let id = url.path[range].components(separatedBy: "/").last ?? ""
        return id.isEmpty ? nil : id
    }

    /// Fetches the full post, trying FxTwitter first and vxTwitter on failure.
    static func fetch(statusID: String, completion: @escaping (FetchedTweet?) -> Void) {
        fetchJSON(from: "https://api.fxtwitter.com/status/\(statusID)") { json in
            if let tweet = parseFxTwitter(json) {
                completion(tweet)
                return
            }
            fetchJSON(from: "https://api.vxtwitter.com/i/status/\(statusID)") { json in
                completion(parseVxTwitter(json))
            }
        }
    }

    /// Inbox title: leading snippet of the post plus the author handle.
    static func documentTitle(for tweet: FetchedTweet) -> String {
        let firstLine = tweet.text
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        var snippet = firstLine.trimmingCharacters(in: .whitespaces)
        if snippet.count > 50 {
            snippet = String(snippet.prefix(50)).trimmingCharacters(in: .whitespaces) + "…"
        }
        if snippet.isEmpty { snippet = "Post" }
        return tweet.authorHandle.isEmpty ? snippet : "\(snippet) — @\(tweet.authorHandle)"
    }

    /// Document body: author byline followed by the post text.
    static func documentBody(for tweet: FetchedTweet) -> String {
        var byline = tweet.authorName
        if !tweet.authorHandle.isEmpty {
            byline += byline.isEmpty ? "@\(tweet.authorHandle)" : " (@\(tweet.authorHandle))"
        }
        return byline.isEmpty ? tweet.text : "\(byline)\n\n\(tweet.text)"
    }

    // MARK: - Providers

    private static func parseFxTwitter(_ json: [String: Any]?) -> FetchedTweet? {
        guard let tweet = json?["tweet"] as? [String: Any],
              let text = cleanText(tweet["text"] as? String) else { return nil }
        let author = tweet["author"] as? [String: Any]
        return FetchedTweet(
            text: text,
            authorName: author?["name"] as? String ?? "",
            authorHandle: author?["screen_name"] as? String ?? ""
        )
    }

    private static func parseVxTwitter(_ json: [String: Any]?) -> FetchedTweet? {
        guard let text = cleanText(json?["text"] as? String) else { return nil }
        return FetchedTweet(
            text: text,
            authorName: json?["user_name"] as? String ?? "",
            authorHandle: json?["user_screen_name"] as? String ?? ""
        )
    }

    // MARK: - Helpers

    private static func fetchJSON(from urlString: String, completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data = data,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil)
                return
            }
            completion(json)
        }.resume()
    }

    /// Strips trailing t.co media stubs and trims whitespace; nil if nothing remains.
    private static func cleanText(_ raw: String?) -> String? {
        guard var text = raw else { return nil }
        text = text.replacingOccurrences(
            of: "(\\s*https://t\\.co/\\w+)+\\s*$",
            with: "",
            options: .regularExpression
        )
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
