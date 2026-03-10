import Foundation
import SwiftUI

struct WorkflowGroup: Identifiable, Codable, Sendable, Hashable {
    var id: UUID
    var name: String
    var icon: String
    var color: GroupColor

    init(id: UUID = UUID(), name: String, icon: String = "folder.fill", color: GroupColor = .blue) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
    }
}

// MARK: - Group Color

enum GroupColor: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case blue, indigo, purple, pink, red, orange, yellow, green, mint, teal, cyan, brown

    var id: String { rawValue }

    var swiftUIColor: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .brown: .brown
        }
    }
}

// MARK: - Curated SF Symbols

enum SFSymbolCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case development = "Development"
    case communication = "Communication"
    case data = "Data"
    case devices = "Devices"
    case nature = "Nature"
    case shapes = "Shapes"

    var id: String { rawValue }

    var symbols: [String] {
        switch self {
        case .general:
            return [
                "folder.fill", "tray.fill", "archivebox.fill", "doc.fill",
                "doc.text.fill", "note.text", "bookmark.fill", "tag.fill",
                "flag.fill", "pin.fill", "mappin", "star.fill",
                "heart.fill", "bolt.fill", "flame.fill", "leaf.fill",
                "clock.fill", "timer", "calendar", "bell.fill",
                "megaphone.fill", "lightbulb.fill", "puzzlepiece.fill", "gearshape.fill",
            ]
        case .development:
            return [
                "terminal.fill", "chevron.left.forwardslash.chevron.right",
                "curlybraces", "function", "hammer.fill", "wrench.fill",
                "screwdriver.fill", "ant.fill", "ladybug.fill", "testtube.2",
                "cpu", "memorychip.fill", "server.rack",
                "externaldrive.fill", "opticaldiscdrive.fill", "network",
            ]
        case .communication:
            return [
                "envelope.fill", "paperplane.fill", "bubble.left.fill",
                "bubble.left.and.bubble.right.fill", "phone.fill",
                "video.fill", "person.fill", "person.2.fill",
                "person.3.fill", "figure.wave", "hand.raised.fill",
                "hand.thumbsup.fill",
            ]
        case .data:
            return [
                "chart.bar.fill", "chart.pie.fill", "chart.line.uptrend.xyaxis",
                "waveform.path.ecg", "cylinder.fill", "square.stack.3d.up.fill",
                "cube.fill", "shippingbox.fill", "tray.2.fill",
                "tablecells.fill", "list.bullet.clipboard.fill", "checklist",
            ]
        case .devices:
            return [
                "desktopcomputer", "laptopcomputer", "iphone",
                "ipad", "applewatch", "headphones",
                "speaker.wave.2.fill", "tv.fill", "gamecontroller.fill",
                "printer.fill", "camera.fill", "photo.fill",
            ]
        case .nature:
            return [
                "sun.max.fill", "moon.fill", "cloud.fill",
                "cloud.bolt.fill", "snowflake", "wind",
                "drop.fill", "mountain.2.fill", "tree.fill",
                "globe.americas.fill", "sparkles", "wand.and.stars",
            ]
        case .shapes:
            return [
                "circle.fill", "square.fill", "triangle.fill",
                "diamond.fill", "pentagon.fill", "hexagon.fill",
                "seal.fill", "shield.fill", "app.fill",
                "rectangle.stack.fill", "circle.grid.3x3.fill", "square.grid.2x2.fill",
            ]
        }
    }
}
