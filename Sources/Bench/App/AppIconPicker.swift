// AppIconPicker.swift — Settings → General → Appearance → App icon: the six
// icons as small tiles, the chosen one ringed (AppIconChoice).
import SwiftUI

/// The ⓘ beside the row: why only the Dock changes.
enum AppIconInfo {
    static let dockOnly = """
        Capsid changes its icon in the Dock while it is open, and in its own Settings and welcome windows. \
        Finder, Launchpad, notifications and the Dock icon of Capsid when it isn't running keep the Clay icon: \
        macOS doesn't let an app change those without altering the app itself, which would break its signature \
        and the permissions you've given it, and every update would undo it.
        """
}

/// The row of tiles. The chosen one has a ring in the accent (clay, since a
/// Settings page tints with it); each is a button named for VoiceOver.
struct AppIconPicker: View {
    @Binding var selection: String

    static let tileSize: CGFloat = 44

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppIconChoice.allCases) { choice in
                AppIconTile(choice: choice, selected: selection == choice.rawValue) {
                    selection = choice.rawValue
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App icon")
    }
}

private struct AppIconTile: View {
    let choice: AppIconChoice
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            picture
                .frame(width: AppIconPicker.tileSize, height: AppIconPicker.tileSize)
                .overlay {
                    // Around the squircle, which fills about four fifths of the picture.
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(.tint, lineWidth: 2)
                        .padding(1.5)
                        .opacity(selected ? 1 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(choice.title)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var picture: some View {
        if let image = choice.picture {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .accessibilityHidden(true)
        } else {
            // Not built by Scripts/build-app.sh (swift run), or the icon didn't compile: the tile's ground alone.
            let tile = choice.tile
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: tile.red / 255, green: tile.green / 255, blue: tile.blue / 255))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
                .padding(4.5)
                .accessibilityHidden(true)
        }
    }
}
