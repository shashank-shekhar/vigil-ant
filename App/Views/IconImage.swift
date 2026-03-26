import SwiftUI

/// Renders an icon from either the Asset Catalog (names starting with "icon-")
/// or SF Symbols. Used for account icons that can be either type.
struct IconImage: View {
    let name: String
    var size: CGFloat = 14

    var body: some View {
        if name.hasPrefix("icon-") {
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: name)
                .font(.system(size: size))
        }
    }
}
