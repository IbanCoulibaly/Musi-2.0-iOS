import SwiftUI

enum TabModel: Hashable {
    case search
    case library
    case playlists
    case youtube

    var title: String {
        switch self {
        case .search: "Search"
        case .library: "Library"
        case .playlists: "Playlists"
        case .youtube: "YouTube"
        }
    }

    var systemImage: String {
        switch self {
        case .search: "magnifyingglass"
        case .library: "music.note.list"
        case .playlists: "rectangle.stack.fill"
        case .youtube: "play.circle.fill"
        }
    }
}
