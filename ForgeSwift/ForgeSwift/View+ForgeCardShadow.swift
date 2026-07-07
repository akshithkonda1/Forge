import SwiftUI

// Consistent card shadow used across Forge views.
// Kept as a thin alias to ForgeElevation.raised (see ForgeElevation.swift)
// so every existing call site keeps its exact current shadow values —
// this is now one shadow implementation, not two that could drift apart.
extension View {
    func forgeCardShadow() -> some View {
        forgeElevation(.raised)
    }
}
