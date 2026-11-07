import SwiftUI
import UIKit
import ForgeCore

/// The hidden tester screen behind Settings › About Forge › long-press the
/// version. It reads ForgeCore's ReliabilityLog: everything on it was
/// measured on this iPhone, and nothing leaves it unless a tester taps
/// Export report and sends the file.
///
/// The two phase-gate numbers:
///   • ARIA replies: turns the chosen path answered without an error, over
///     all turns. A cloud failure rescued by the on-device fallback counts
///     as a miss: the person got a reply, the infrastructure did not.
///   • Crash-free sessions: foreground sessions that did not end with the
///     process dying on screen. Xcode runs are left out.
struct ReliabilityView: View {
    @State private var summary: ReliabilitySummary?
    @State private var exportURL: URL?
    @State private var confirmingReset = false
    @State private var resets = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            ForgeScreenStack {
                ForgePageHeader(title: "Reliability", subtitle: subtitle)
                if let summary {
                    gateCard(summary)
                    latencyCard(summary.aria)
                    errorsCard(summary.recentErrors)
                    appleCard(summary.apple)
                    actions
                } else {
                    ProgressView()
                        .tint(.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .forgeScreenBackground(accent: .ember)
        .navigationTitle("Reliability")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .confirmationDialog(
            "Start a new phase window?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset counters", role: .destructive) {
                Task {
                    await ReliabilityLog.shared.resetWindow()
                    resets += 1
                    await reload()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("ARIA and session counts start again from zero. Apple's crash and launch reports are kept.")
        }
        .forgeHaptic(.success, trigger: resets)
    }

    private var subtitle: String {
        guard let summary else { return "On this iPhone" }
        let since = summary.windowStartedAt.formatted(date: .abbreviated, time: .shortened)
        return "On this iPhone since \(since)"
    }

    // MARK: Phase gate

    private func gateCard(_ summary: ReliabilitySummary) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Phase gate", meta: "Target \(Self.percent(summary.gateTarget))")
            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                ForgeMetricRow(
                    label: "ARIA replies",
                    value: Self.percent(summary.aria.successRate),
                    tint: Self.tint(summary.aria.gate),
                    detail: "\(summary.aria.successes.formatted()) of \(summary.aria.total.formatted()) succeeded · \(summary.aria.gate.label)"
                )
                ForgeMetricRow(
                    label: "Crash-free sessions",
                    value: Self.percent(summary.sessions.crashFreeRate),
                    tint: Self.tint(summary.sessions.gate),
                    detail: "\((summary.sessions.total - summary.sessions.abnormal).formatted()) of \(summary.sessions.total.formatted()) sessions · \(summary.sessions.gate.label)"
                )
            }
            Text(gateNote(summary))
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeContentCard()
    }

    private func gateNote(_ summary: ReliabilitySummary) -> String {
        var parts: [String] = []
        if summary.aria.fallbacks > 0 {
            parts.append("\(summary.aria.fallbacks.formatted()) cloud turns fell back to on-device and count as misses.")
        }
        if summary.sessions.excludedDebugger > 0 {
            parts.append("\(summary.sessions.excludedDebugger.formatted()) Xcode sessions left out.")
        }
        parts.append("99.9% needs at least \(summary.gateMinimumSample.formatted()) of each before it means anything.")
        return parts.joined(separator: " ")
    }

    // MARK: Latency

    private func latencyCard(_ aria: AriaReliabilityStats) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("ARIA latency", meta: "Last \(aria.latencySample.formatted()) turns")
            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                ForgeMetricRow(label: "Median (p50)", value: Self.duration(aria.p50Ms))
                ForgeMetricRow(label: "Slowest 5% (p95)", value: Self.duration(aria.p95Ms))
            }
            if !aria.byRoute.isEmpty {
                VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                    ForEach(aria.byRoute) { route in
                        ForgeMetricRow(
                            label: route.route.label,
                            value: Self.percent(route.successRate),
                            detail: "\(route.counts.counted.formatted()) turns · p50 \(Self.duration(route.p50Ms)) · p95 \(Self.duration(route.p95Ms))"
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeContentCard()
    }

    // MARK: Errors

    private func errorsCard(_ errors: [ReliabilityRecentError]) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Recent errors", meta: errors.isEmpty ? "None" : "\(errors.count)")
            if errors.isEmpty {
                Text("Nothing has failed in this window.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            } else {
                VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                    ForEach(Array(errors.enumerated()), id: \.offset) { _, error in
                        errorRow(error)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeContentCard()
    }

    private func errorRow(_ error: ReliabilityRecentError) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
            HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.sm) {
                Text(errorTitle(error))
                    .font(HomeType.label)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                Spacer(minLength: FDS.Spacing.sm)
                Text(error.at.formatted(.relative(presentation: .named)))
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            Text(errorDetail(error))
                .font(HomeType.micro)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
        .accessibilityElement(children: .combine)
    }

    private func errorTitle(_ error: ReliabilityRecentError) -> String {
        if let route = error.route {
            return "\(error.operation.label) · \(route.label)"
        }
        return "\(error.area.label) · \(error.operation.label)"
    }

    private func errorDetail(_ error: ReliabilityRecentError) -> String {
        var parts: [String] = [error.error?.kind.label ?? "Unknown"]
        if let code = error.error?.code {
            parts.append("code \(code)")
        }
        if error.outcome == .fallback {
            parts.append("answered on device instead")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Apple (MetricKit)

    private func appleCard(_ apple: AppleReliabilityStats) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Apple diagnostics", meta: apple.latestPeriodEnd.map { "Updated \($0.formatted(.relative(presentation: .named)))" } ?? "Waiting")
            if apple.payloads == 0 && apple.diagnosticsByKind.isEmpty && apple.latestPeriodEnd == nil {
                Text("Apple sends launch, hang and exit numbers about once a day, and crash or hang reports on the launch after one happens. The first ones show up here a day or so after install.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            } else {
                VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                    ForgeMetricRow(
                        label: "Crash-free exits (Apple)",
                        value: Self.percent(apple.foregroundCrashFreeRate),
                        detail: "\(apple.foregroundExits.crashLike.formatted()) crash-like of \(apple.foregroundExits.total.formatted()) on-screen exits"
                    )
                    ForgeMetricRow(label: "Launch, median", value: Self.duration(apple.launchP50Ms.map { Int($0.rounded()) }))
                    ForgeMetricRow(label: "Resume, median", value: Self.duration(apple.resumeP50Ms.map { Int($0.rounded()) }))
                    ForgeMetricRow(
                        label: "Hang time",
                        value: apple.hangSecondsPerHour.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                        unit: apple.hangSecondsPerHour == nil ? nil : "s / hr"
                    )
                    ForgeMetricRow(
                        label: "Peak memory",
                        value: apple.peakMemoryMB.map { Int($0.rounded()).formatted() } ?? "—",
                        unit: apple.peakMemoryMB == nil ? nil : "MB"
                    )
                    ForEach(ReliabilityDiagnosticKind.allCases, id: \.self) { kind in
                        if let count = apple.diagnosticsByKind[kind.rawValue], count > 0 {
                            ForgeMetricRow(label: "\(kind.label) reports", value: count.formatted())
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeContentCard()
    }

    // MARK: Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.tileGap) {
            if let exportURL {
                ShareLink(item: exportURL) {
                    ReliabilityActionLabel(title: "Export report", icon: "square.and.arrow.up", accent: .ember)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { ForgeHaptics.play(.press) })
            }
            ForgeSecondaryButton(title: "Start new phase window", icon: "arrow.counterclockwise", accent: .textSecondary) {
                ForgeHaptics.play(.warning)
                confirmingReset = true
            }
            Text("The report is JSON: rates, latencies, error kinds and codes, sessions, and Apple's crash and launch summaries. It never contains messages or health data.")
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
    }

    // MARK: Data

    private func reload() async {
        let build = ReliabilityReport.Build(
            appVersion: ForgeAppInfo.shortVersion,
            appBuild: ForgeAppInfo.buildNumber,
            osVersion: UIDevice.current.systemVersion,
            deviceModel: UIDevice.current.model,
            configuration: Self.configuration
        )
        let report = await ReliabilityLog.shared.report(build: build)
        summary = report.summary
        exportURL = Self.writeExport(report)
    }

    private static func writeExport(_ report: ReliabilityReport) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let name = "forge-reliability-\(formatter.string(from: report.summary.generatedAt)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try report.jsonData().write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }

    private static var configuration: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    // MARK: Formatting

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.percent.precision(.fractionLength(2)))
    }

    static func duration(_ ms: Int?) -> String {
        guard let ms else { return "—" }
        if ms < 1_000 { return "\(ms) ms" }
        return (Double(ms) / 1_000).formatted(.number.precision(.fractionLength(1))) + " s"
    }

    static func tint(_ status: PhaseGateStatus) -> Color? {
        switch status {
        case .meets: return .success
        case .below: return .danger
        case .tooFewToJudge, .noData: return nil
        }
    }
}

/// Same shape as ForgeSecondaryButton, for ShareLink (which needs a label,
/// not an action).
private struct ReliabilityActionLabel: View {
    let title: String
    let icon: String
    let accent: Color

    var body: some View {
        HStack(spacing: FDS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: ForgeUX.icon, weight: .semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(HomeType.label)
                .lineLimit(1)
                .minimumScaleFactor(ForgeLayout.labelMinScale)
        }
        .foregroundStyle(accent)
        .frame(maxWidth: .infinity)
        .frame(minHeight: ForgeUX.minTap)
        .padding(.horizontal, FDS.Spacing.lg)
        .background(accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                .stroke(accent.opacity(0.28), lineWidth: ForgeUX.hairline)
        )
        .contentShape(Rectangle())
    }
}
