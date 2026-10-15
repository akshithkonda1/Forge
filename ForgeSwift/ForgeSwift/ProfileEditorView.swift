import SwiftUI
import PhotosUI
import UIKit
import ForgeCore

struct ProfileEditorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: AppStore

    @State private var name = ""
    @State private var age = ""
    @State private var weight = ""
    @State private var heightFeet = ""
    @State private var heightInches = ""
    @State private var experience: ExperienceLevel = .beginner
    @State private var gender: Gender = .preferNotToSay
    @State private var biologicalSex: BiologicalSex?

    @State private var photoItem: PhotosPickerItem?
    @State private var pendingPhoto: UIImage?
    @State private var removePhoto = false
    @State private var showCamera = false
    @State private var isLoadingPhoto = false
    @State private var showPhotoPicker = false
    @State private var errorMessage: String?

    @ScaledMetric(relativeTo: .largeTitle) private var editorAvatarSize: CGFloat = 110

    private static let lbsPerKg = 2.20462
    private static let cmPerInch = 2.54

    private var currentAvatarFileName: String? {
        removePhoto ? nil : store.userProfile.avatarFileName
    }

    private var hasPhoto: Bool {
        pendingPhoto != nil || (!removePhoto && store.userProfile.avatarFileName != nil)
    }

    // MARK: Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Your name can't be empty."
            return
        }

        // Empty means "leave it alone"; a filled field with junk in it is an error the
        // user should see rather than have silently dropped, which is what the old
        // `Int(age)` optional-chain did.
        let ageText = age.trimmingCharacters(in: .whitespaces)
        var newAge: Int?
        if !ageText.isEmpty {
            guard let parsed = Int(ageText), (13...120).contains(parsed) else {
                errorMessage = "Enter an age between 13 and 120."
                return
            }
            newAge = parsed
        }

        let weightText = weight.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        var newWeightKg: Double?
        if !weightText.isEmpty {
            guard let lbs = Double(weightText), (50...800).contains(lbs) else {
                errorMessage = "Enter a weight between 50 and 800 lbs."
                return
            }
            newWeightKg = lbs / Self.lbsPerKg
        }

        var newHeightCm: Double?
        let feetText = heightFeet.trimmingCharacters(in: .whitespaces)
        let inchesText = heightInches.trimmingCharacters(in: .whitespaces)
        if !feetText.isEmpty || !inchesText.isEmpty {
            let feet = Int(feetText) ?? 0
            let inches = Int(inchesText) ?? 0
            let totalInches = Double(feet * 12 + inches)
            guard (36...96).contains(totalInches) else {
                errorMessage = "Enter a height between 3'0\" and 8'0\"."
                return
            }
            newHeightCm = totalInches * Self.cmPerInch
        }

        if let pendingPhoto {
            guard store.setProfilePhoto(pendingPhoto) else {
                errorMessage = "Couldn't save that photo. Try a different image."
                return
            }
        } else if removePhoto {
            store.removeProfilePhoto()
        }

        store.updateProfile(
            name: trimmedName == store.userProfile.name ? nil : trimmedName,
            experienceLevel: experience == store.userProfile.experienceLevel ? nil : experience,
            age: newAge,
            weightKg: newWeightKg,
            heightCm: newHeightCm,
            gender: gender == store.userProfile.gender ? nil : gender,
            biologicalSex: biologicalSex == store.userProfile.biologicalSex ? nil : biologicalSex
        )
        FDS.notificationHaptic(.success)
        dismiss()
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ForgeLayout.sectionGap) {
                    avatarEditor
                    identityCard
                    bodyCard
                    trainingCard
                }
                .forgeScreenInsets(top: FDS.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .forgeScreenBackground(accent: .steel)
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .tint(Color.ember)
                        .disabled(!isDirty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
            }
            .onAppear(perform: loadCurrentValues)
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $photoItem,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                loadPickedPhoto(item)
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView { image in
                    pendingPhoto = image
                    removePhoto = false
                }
                .ignoresSafeArea()
            }
            .alert("Check that", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    /// True once any field, picker or photo differs from the saved profile.
    private var isDirty: Bool {
        if pendingPhoto != nil || removePhoto { return true }
        let profile = store.userProfile
        if name != profile.name { return true }
        if age != (profile.age.map(String.init) ?? "") { return true }
        if weight != savedWeightText(profile) { return true }
        let savedHeight = savedHeightText(profile)
        if heightFeet != savedHeight.feet || heightInches != savedHeight.inches { return true }
        if experience != profile.experienceLevel { return true }
        if gender != profile.gender { return true }
        return biologicalSex != profile.biologicalSex
    }

    private func savedWeightText(_ profile: UserProfile) -> String {
        guard let kg = profile.weight else { return "" }
        return String(Int((kg * Self.lbsPerKg).rounded()))
    }

    private func savedHeightText(_ profile: UserProfile) -> (feet: String, inches: String) {
        guard let cm = profile.height else { return ("", "") }
        let totalInches = Int((cm / Self.cmPerInch).rounded())
        return (String(totalInches / 12), String(totalInches % 12))
    }

    private func loadCurrentValues() {
        let profile = store.userProfile
        name = profile.name
        age = profile.age.map(String.init) ?? ""
        weight = profile.weight.map { String(Int(($0 * Self.lbsPerKg).rounded())) } ?? ""
        if let cm = profile.height {
            let totalInches = Int((cm / Self.cmPerInch).rounded())
            heightFeet = String(totalInches / 12)
            heightInches = String(totalInches % 12)
        }
        experience = profile.experienceLevel
        gender = profile.gender
        biologicalSex = profile.biologicalSex
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem) {
        isLoadingPhoto = true
        Task {
            defer { isLoadingPhoto = false }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Couldn't read that image."
                return
            }
            pendingPhoto = image
            removePhoto = false
            FDS.haptic(.light)
        }
    }

    // MARK: Sections

    /// The avatar is the photo control: one tap opens library, camera and remove.
    private var avatarEditor: some View {
        VStack(spacing: ForgeLayout.rowGap) {
            Menu {
                Button {
                    showPhotoPicker = true
                } label: {
                    Label(hasPhoto ? "Change photo" : "Add photo", systemImage: "photo.on.rectangle")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera")
                    }
                }
                if hasPhoto {
                    Button(role: .destructive) {
                        pendingPhoto = nil
                        photoItem = nil
                        removePhoto = true
                        FDS.haptic(.press)
                    } label: {
                        Label("Remove profile photo", systemImage: "trash")
                    }
                }
            } label: {
                avatarLabel
            }
            .accessibilityLabel(hasPhoto ? "Change photo" : "Add photo")

            if removePhoto && pendingPhoto == nil {
                Text("Photo will be removed when you save.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .forgeWrapping()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var avatarLabel: some View {
        let size = ForgeLayout.scaledCap(editorAvatarSize, base: 110, maxGrowth: 1.25)
        return ZStack(alignment: .bottomTrailing) {
            avatarImage(size: size)
                .overlay(Circle().stroke(Color.ember.opacity(0.4), lineWidth: 2))
                .accessibilityHidden(true)
            avatarBadge
        }
        .padding(FDS.Spacing.sm)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func avatarImage(size: CGFloat) -> some View {
        if let pendingPhoto {
            Image(uiImage: pendingPhoto)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            ProfileAvatarView(
                fileName: currentAvatarFileName,
                initials: store.userProfile.initials,
                size: size,
                showsRing: false
            )
        }
    }

    @ViewBuilder
    private var avatarBadge: some View {
        if isLoadingPhoto {
            ProgressView()
                .tint(.white)
                .frame(width: ForgeUX.minTap - 8, height: ForgeUX.minTap - 8)
                .background(Circle().fill(Color.ember))
        } else {
            ZStack {
                Circle().fill(Color.background).frame(width: 40, height: 40)
                Circle().fill(Color.ember).frame(width: 36, height: 36)
                Image(systemName: "camera.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .accessibilityHidden(true)
        }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Identity")

            VStack(spacing: 0) {
                ProfileFieldRow(label: "Name", placeholder: "Your name", text: $name)

                ProfileFieldDivider()

                ProfilePickerRow(label: "Gender") {
                    Picker("Gender", selection: $gender) {
                        ForEach(Gender.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(.ember)
                }

                ProfileFieldDivider()

                // Cycle health keys off biological sex, so it has to be editable after
                // onboarding rather than locked in forever at first launch.
                ProfilePickerRow(
                    label: "Biological sex",
                    footnote: "Used to configure cycle health features. Stays on your device."
                ) {
                    Picker("Biological sex", selection: $biologicalSex) {
                        Text("Not set").tag(BiologicalSex?.none)
                        ForEach(BiologicalSex.allCases) { option in
                            Text(option.label).tag(BiologicalSex?.some(option))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(.ember)
                }
            }
        }
        .forgeContentCard()
    }

    private var bodyCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Body")

            VStack(spacing: 0) {
                ProfileFieldRow(label: "Age", placeholder: "Age", text: $age, keyboardType: .numberPad)

                ProfileFieldDivider()

                ProfileFieldRow(label: "Weight (lbs)", placeholder: "Weight", text: $weight, keyboardType: .decimalPad)

                ProfileFieldDivider()

                heightRow
            }
        }
        .forgeContentCard()
    }

    private var heightRow: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
            Text("Height")
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .layoutPriority(1)
            HStack(spacing: ForgeLayout.rowGap) {
                heightField(placeholder: "5", text: $heightFeet, unit: "ft")
                heightField(placeholder: "10", text: $heightInches, unit: "in")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .frame(minHeight: ForgeUX.minTap)
    }

    private func heightField(placeholder: String, text: Binding<String>, unit: String) -> some View {
        HStack(spacing: FDS.Spacing.xs) {
            TextField(placeholder, text: text)
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 36, maxWidth: 64, minHeight: ForgeUX.minTap)
            Text(unit)
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Height in \(unit == "ft" ? "feet" : "inches")")
    }

    private var trainingCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Training")

            ProfilePickerRow(label: "Experience level", footnote: experience.description) {
                Picker("Experience", selection: $experience) {
                    ForEach(ExperienceLevel.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(.ember)
            }
        }
        .forgeContentCard()
    }
}

/// Hairline between rows of an editor card.
struct ProfileFieldDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.borderHairline)
            .frame(height: 1)
            .padding(.vertical, 2)
            .accessibilityHidden(true)
    }
}

struct ProfilePickerRow<Content: View>: View {
    let label: String
    var footnote: String?
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize) private var typeSize

    init(label: String, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
            ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
                Text(label)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .layoutPriority(1)
                content
                    .frame(
                        maxWidth: .infinity,
                        minHeight: ForgeUX.minTap,
                        alignment: typeSize.isAccessibilitySize ? .leading : .trailing
                    )
            }
            .padding(.vertical, ForgeLayout.rowVerticalPadding)

            if let footnote {
                Text(footnote)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
                    .padding(.bottom, ForgeLayout.rowVerticalPadding)
            }
        }
    }
}

/// Minimal camera capture. `PhotosPicker` covers the library; this covers "take one now",
/// which the old editor's dead camera button implied but never delivered.
struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraCaptureView

        init(_ parent: CameraCaptureView) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            if let image { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct ProfileFieldRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    @FocusState private var isFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
            Text(label)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .layoutPriority(1)

            TextField(placeholder, text: $text)
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                .keyboardType(keyboardType)
                .focused($isFocused)
                .frame(
                    maxWidth: .infinity,
                    minHeight: ForgeUX.minTap,
                    alignment: typeSize.isAccessibilitySize ? .leading : .trailing
                )
                .accessibilityLabel(label)
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }
}
