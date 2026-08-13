import SwiftUI
import UIKit
import ForgeCore

/// Official product photo for a catalog SKU. Falls back to the SF Symbol
/// if that photo is not in the asset catalog yet.
struct DeviceProductImage: View {
    let assetName: String
    var photoURL: URL? = nil
    var fallbackSymbol: String = "sensor.tag.radiowaves.forward"
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 12

    init(device: HealthDevice, size: CGFloat = 56, cornerRadius: CGFloat = 12) {
        self.assetName = device.photoAssetName
        self.photoURL = device.photoURL.flatMap(URL.init(string:))
        self.fallbackSymbol = device.artwork.symbolName
        self.size = size
        self.cornerRadius = cornerRadius
    }

    init(assetName: String, fallbackSymbol: String = "sensor.tag.radiowaves.forward", size: CGFloat = 56, cornerRadius: CGFloat = 12) {
        self.assetName = assetName
        self.fallbackSymbol = fallbackSymbol
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Group {
            if UIImage(named: assetName) != nil {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else if let photoURL {
                AsyncImage(url: photoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        symbolFallback
                    }
                }
            } else {
                symbolFallback
            }
        }
        .frame(width: size, height: size)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private var symbolFallback: some View {
        ZStack {
            Color.surfaceElevated
            Image(systemName: fallbackSymbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundColor(.textSecondary)
        }
    }
}

struct DeviceArtworkStack: View {
    let devices: [HealthDevice]
    var size: CGFloat = 44

    var body: some View {
        let shown = Array(devices.prefix(3))
        ZStack(alignment: .leading) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, device in
                DeviceProductImage(device: device, size: size, cornerRadius: 10)
                    .offset(x: CGFloat(index) * (size * 0.42))
                    .zIndex(Double(shown.count - index))
            }
        }
        .frame(
            width: size + CGFloat(max(0, shown.count - 1)) * (size * 0.42),
            height: size,
            alignment: .leading
        )
    }
}
