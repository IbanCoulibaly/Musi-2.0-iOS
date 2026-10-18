import Foundation

struct YouTubeVideo: Identifiable {
    var id: String { videoId }
    let videoId: String
    let title: String
    let thumbnailURL: URL?
}

struct YouTubeSearchResponse: Codable {
    let items: [YouTubeSearchItem]
}

struct YouTubeSearchItem: Codable {
    let id: YouTubeSearchId
    let snippet: YouTubeSearchSnippet
}

struct YouTubeSearchId: Codable {
    let videoId: String
}

struct YouTubeSearchSnippet: Codable {
    let title: String
    let thumbnails: YouTubeThumbnails
}

struct YouTubeThumbnails: Codable {
    let `default`: YouTubeThumbnail
    let medium: YouTubeThumbnail?

    var bestAvailable: YouTubeThumbnail {
        medium ?? `default`
    }
}

struct YouTubeThumbnail: Codable {
    let url: URL
}

func searchYouTube(query: String, completion: @escaping ([YouTubeVideo]) -> Void) {
    guard !query.isEmpty else {
        completion([])
        return
    }

    var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")
    components?.queryItems = [
        URLQueryItem(name: "part", value: "snippet"),
        URLQueryItem(name: "q", value: query),
        URLQueryItem(name: "type", value: "video"),
        URLQueryItem(name: "maxResults", value: "20"),
        URLQueryItem(name: "key", value: Secrets.youTubeAPIKey)
    ]

    guard let url = components?.url else {
        completion([])
        return
    }
        
    let task = URLSession.shared.dataTask(with: url) { data, response, error in
        if let data {
            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(YouTubeSearchResponse.self, from: data)
                let videos = response.items.map { item in
                    YouTubeVideo(
                        videoId: item.id.videoId,
                        title: item.snippet.title,
                        thumbnailURL: item.snippet.thumbnails.bestAvailable.url
                    )
                }
                DispatchQueue.main.async {
                    completion(videos) // Send the result back
                }
            } catch {
                print("❌ Error decoding response: \(error)")
                DispatchQueue.main.async {
                    completion([])
                }
            }
        } else {
            if let error {
                print("❌ YouTube search failed: \(error)")
            }
            DispatchQueue.main.async {
                completion([])
            }
        }
    }
    task.resume()
}
