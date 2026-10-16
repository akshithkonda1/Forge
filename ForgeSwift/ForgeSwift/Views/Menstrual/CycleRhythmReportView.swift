import SwiftUI
import ForgeCore

/// 3 / 6 / 12-month clinician pack — templated on-device from Apple Cycle Tracking.
struct CycleRhythmReportView: View {
    @ObservedObject var cycleStore: MenstrualHealthStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var window: CycleRhythmReport.Window = .twelve
    @State private var isRefreshing = false
    @State private var pdfURL: URL?
    @State private var linkBusy = false
    @State private var linkURL: URL?
    @State private var linkError: String?
    @State private var linkExpires: String?
    @State private var showFullReport = false

    private static let monthParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    private var months: [CycleMonthlyDigest] {
        cycleStore.loadRecentMonthlyDigests(windowMonths: window.rawValue)
    }

    private var report: String {
        cycleStore.clinicianRhythmReportText(windowMonths: window.rawValue)
    }

    private var windowOptions: [ForgeSegmentOption<CycleRhythmReport.Window>] {
        CycleRhythmReport.Window.allCases.map { w in
            ForgeSegmentOption(value: w, title: w.label)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ForgeScreenStack(top: FDS.Spacing.lg) {
                    header

                    ForgeSegmentedControl(windowOptions, selection: $window, accent: .vitality)

                    summaryHero

                    actionButtons

                    if months.isEmpty {
                        ForgeEmptyStateCard(
                            icon: "calendar.badge.clock",
                            title: "Your pack builds itself",
                            message: "Keep logging. Each day writes to Apple Health. After a few cycles this becomes a 3, 6, or 12-month evidence pack.",
                            accent: .vitality
                        )
                    } else {
                        monthsCard
                    }

                    reportPreviewCard
                }
            }
            .forgeScreenBackground(accent: .ember)
            .navigationTitle("Apple Cycle report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { rebuildPDF() }
            .onChange(of: window) { _, _ in rebuildPDF() }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Header and hero

    private var header: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForgeAdaptiveStack(spacing: FDS.Spacing.sm) {
                Text("Rhythm report")
                    .font(HomeType.sessionTitle)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HudVibeChip(label: "Apple Cycle", energy: Color.vitality)
            }
            Text("Forge reads what it already wrote to Apple Cycle Tracking, then fills this template on your iPhone. Share the PDF via Mail, Files, or MyChart. A temporary private link is optional and expires in a day — nothing is stored in a Forge database.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
    }

    private var summaryHero: some View {
        let snap = cycleStore.snapshot
        return VStack(alignment: .leading, spacing: ForgeLayout.heroGap) {
            ForgeStatGrid(columns: 3) {
                ForgeStatTile(
                    label: "Cycle",
                    value: "\(Int(snap.cycleLengthMedian.rounded()))",
                    unit: "d",
                    energy: Color.ember
                )
                ForgeStatTile(
                    label: "Period",
                    value: "\(Int(snap.periodLengthMedian.rounded()))",
                    unit: "d",
                    energy: Color.alert
                )
                if let mae = cycleStore.accuracyReport.maeDays {
                    ForgeStatTile(
                        label: "Accuracy",
                        value: String(format: "±%.1f", mae),
                        unit: "d",
                        energy: Color.vitality
                    )
                }
            }

            if let pdfURL {
                ShareLink(item: pdfURL) {
                    ReportActionLabel(
                        title: "Share PDF with my clinician",
                        icon: "square.and.arrow.up",
                        style: .primary
                    )
                }
                .buttonStyle(ForgePressStyle())
                .accessibilityHint("Opens the system share sheet with a PDF. You choose Mail, Files, MyChart, or AirDrop.")
            }
        }
        .hudPlate(energy: Color.ember)
        .accessibilityElement(children: .contain)
    }

    // MARK: Actions

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.tileGap) {
            ForgeSecondaryButton(
                title: isRefreshing ? "Reading Apple Cycle…" : "Refresh from Apple Cycle",
                icon: "arrow.triangle.2.circlepath",
                accent: .vitality
            ) {
                isRefreshing = true
                Task {
                    _ = await cycleStore.refreshClinicianReportFromAppleHealth(windowMonths: window.rawValue)
                    rebuildPDF()
                    isRefreshing = false
                }
            }
            .disabled(isRefreshing)
            .opacity(isRefreshing ? 0.6 : 1)

            ForgeSecondaryButton(
                title: linkBusy ? "Minting a 24-hour link…" : "Temporary private link (24h)",
                icon: "link",
                accent: .vitality
            ) {
                Task { await mintTemporaryLink() }
            }
            .disabled(linkBusy || pdfURL == nil)
            .opacity(linkBusy || pdfURL == nil ? 0.6 : 1)

            if let linkURL {
                ShareLink(item: linkURL) {
                    ReportActionLabel(
                        title: "Share expiring link",
                        icon: "square.and.arrow.up",
                        style: .secondary
                    )
                }
                .buttonStyle(ForgePressStyle())
                if let linkExpires {
                    Text("Expires \(linkExpires). Not stored on Forge servers.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .forgeWrapping()
                }
            }
            if let linkError {
                Text(linkError)
                    .font(HomeType.body)
                    .foregroundStyle(Color.ember)
                    .forgeWrapping()
            }
        }
    }

    // MARK: Months

    private var monthsCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("MONTHS IN THIS PACK")
            VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
                ForEach(months) { month in
                    monthRow(month)
                }
            }
        }
        .forgeContentCard(tint: .vitality)
    }

    private func monthRow(_ month: CycleMonthlyDigest) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.tileGap) {
            Text(monthTitle(month.monthKey))
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ForgeStatGrid(columns: 3) {
                ForgeStatTile(label: "Days logged", value: "\(month.daysLogged)", energy: Color.vitality)
                ForgeStatTile(label: "Bleeding", value: "\(month.bleedingDays)", energy: Color.alert)
                ForgeStatTile(label: "Starts", value: "\(month.cycleStarts)", energy: Color.ember)
            }
        }
    }

    /// "2026-09" reads as a month name; an unparseable key is shown as-is.
    private func monthTitle(_ key: String) -> String {
        guard let date = Self.monthParser.date(from: key) else { return key }
        return Self.monthTitleFormatter.string(from: date)
    }

    // MARK: Report text

    private var reportPreviewCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            Text(report)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .textSelection(.enabled)
                .lineLimit(showFullReport ? nil : 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeWell()

            ForgeTextLink(title: "Preview report text", accent: .ember, expanded: showFullReport) {
                withAnimation(reduceMotion ? nil : ForgeMotion.smooth) {
                    showFullReport.toggle()
                }
            }
        }
        .forgeContentCard()
    }

    // MARK: Behavior (unchanged)

    private func rebuildPDF() {
        let dayKey = CycleDayKey.key()
        let title = "FORGE — \(window.rawValue)-MONTH TRACKING SUMMARY"
        pdfURL = try? CycleReportPDF.writeTemporaryPDF(
            windowMonths: window.rawValue,
            dayKey: dayKey,
            title: title,
            body: report
        )
        linkURL = nil
        linkError = nil
        linkExpires = nil
    }

    private func mintTemporaryLink() async {
        guard let pdfURL, let data = try? Data(contentsOf: pdfURL) else {
            linkError = "Could not build the PDF on this iPhone."
            return
        }
        linkBusy = true
        linkError = nil
        defer { linkBusy = false }
        do {
            let ticket = try await CycleReportUploadClient.requestTicket(
                byteLength: data.count,
                windowMonths: window.rawValue
            )
            try await CycleReportUploadClient.upload(pdf: data, ticket: ticket)
            linkURL = ticket.getUrl
            linkExpires = ticket.expiresAt
        } catch is ForgeAPI.Failure {
            linkError = "Share the PDF from this iPhone — a cloud link needs sign-in and is optional."
        } catch {
            linkError = "Share the PDF from this iPhone — a cloud link is optional and wasn’t available."
        }
    }
}

/// Visual label for a `ShareLink`, drawn to match `ForgePrimaryButton` and
/// `ForgeSecondaryButton` (a `ShareLink` has no action closure to hand to them).
private struct ReportActionLabel: View {
    enum Style {
        case primary
        case secondary
    }

    let title: String
    let icon: String
    let style: Style

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
    }

    var body: some View {
        switch style {
        case .primary:
            primaryBody
        case .secondary:
            secondaryBody
        }
    }

    private var primaryBody: some View {
        HStack(spacing: FDS.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: ForgeUX.icon, weight: .semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(HomeType.cta)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: FDS.Spacing.sm)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .accessibilityHidden(true)
        }
        .foregroundColor(.white)
        .padding(.vertical, FDS.Spacing.md)
        .padding(.horizontal, FDS.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap + 8, alignment: .leading)
        .background {
            ZStack {
                FDS.Gradient.ember
                LinearGradient.premiumChrome
            }
        }
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.20), lineWidth: ForgeUX.hairline))
    }

    private var secondaryBody: some View {
        HStack(spacing: FDS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: ForgeUX.icon, weight: .semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(HomeType.label)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.vitality)
        .frame(maxWidth: .infinity)
        .frame(minHeight: ForgeUX.minTap)
        .padding(.horizontal, FDS.Spacing.lg)
        .background(Color.vitality.opacity(0.12))
        .clipShape(shape)
        .overlay(shape.stroke(Color.vitality.opacity(0.28), lineWidth: ForgeUX.hairline))
    }
}

struct CycleTrainingPrescriptionCard: View {
    let prescription: CycleTrainingPrescription
    var onAskARIA: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("TODAY'S TRAINING")

            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(prescription.headline)
                    .font(HomeType.sessionTitle)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                Text(prescription.volumeLine)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }

            ForgeEqualColumnsLayout(
                columns: typeSize.isAccessibilitySize ? 1 : 2,
                spacing: ForgeLayout.tileGap
            ) {
                fact(label: "Intensity", text: prescription.intensityLine)
                fact(label: "Return", text: prescription.returnLine)
            }

            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                ForgeTextLink(title: "Ask ARIA to shape this", accent: .ember) {
                    onAskARIA()
                }
                Text(prescription.disclaimer)
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }
        }
        .forgeContentCard(tint: .ember)
        .accessibilityElement(children: .contain)
    }

    private func fact(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
            Text(label)
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .textCase(.uppercase)
            Text(text)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .forgeWell()
        .accessibilityElement(children: .combine)
    }
}
