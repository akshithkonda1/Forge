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
    @State private var errorMessage: String?

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
                VStack(spacing: 24) {
                    avatarEditor
                    identityFields
                    bodyFields
                    trainingFields
                    saveButton
                }
                .padding()
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.textSecondary)
                }
            }
            .onAppear(perform: loadCurrentValues)
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

    private var avatarEditor: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let pendingPhoto {
                        Image(uiImage: pendingPhoto)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 110, height: 110)
                            .clipShape(Circle())
                    } else {
                        ProfileAvatarView(
                            fileName: currentAvatarFileName,
                            initials: store.userProfile.initials,
                            size: 110,
                            showsRing: false
                        )
                    }
                }
                .overlay(Circle().stroke(Color.ember.opacity(0.4), lineWidth: 2))

                if isLoadingPhoto {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.ember))
                } else {
                    ZStack {
                        Circle().fill(Color.background).frame(width: 36, height: 36)
                        Circle().fill(Color.ember).frame(width: 32, height: 32)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    }
                    .offset(x: 2, y: 2)
                }
            }
            .accessibilityHidden(true)

            HStack(spacing: 10) {
                // The picker is its own control rather than a dialog action, because
                // PhotosPicker must be present in the hierarchy to present its sheet.
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Label(hasPhoto ? "Change photo" : "Add photo", systemImage: "photo.on.rectangle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.ember)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color.ember.opacity(0.12))
                        .cornerRadius(100)
                }

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Color.surfaceElevated)
                            .cornerRadius(100)
                    }
                    .buttonStyle(.plain)
                }

                if hasPhoto {
                    Button {
                        pendingPhoto = nil
                        photoItem = nil
                        removePhoto = true
                        FDS.haptic(.light)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.danger)
                            .padding(9)
                            .background(Color.danger.opacity(0.12))
                            .cornerRadius(100)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove profile photo")
                }
            }

            if removePhoto && pendingPhoto == nil {
                Text("Photo will be removed when you save.")
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(.top, 12)
    }

    private var identityFields: some View {
        VStack(spacing: 16) {
            ProfileFieldRow(label: "Name", placeholder: "Your name", text: $name)

            ProfilePickerRow(label: "Gender") {
                Picker("Gender", selection: $gender) {
                    ForEach(Gender.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(.ember)
            }

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
                .pickerStyle(.menu)
                .tint(.ember)
            }
        }
    }

    private var bodyFields: some View {
        VStack(spacing: 16) {
            ProfileFieldRow(label: "Age", placeholder: "Age", text: $age, keyboardType: .numberPad)
            ProfileFieldRow(label: "Weight (lbs)", placeholder: "Weight", text: $weight, keyboardType: .decimalPad)

            VStack(alignment: .leading, spacing: 8) {
                Text("Height")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
                HStack(spacing: 10) {
                    heightField(placeholder: "5", text: $heightFeet, unit: "ft")
                    heightField(placeholder: "10", text: $heightInches, unit: "in")
                }
            }
        }
    }

    private func heightField(placeholder: String, text: Binding<String>, unit: String) -> some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .keyboardType(.numberPad)
            Text(unit)
                .font(.system(size: 13))
                .foregroundColor(.textTertiary)
        }
        .padding(14)
        .background(Color.surface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.borderColor, lineWidth: 1))
        .accessibilityLabel("Height in \(unit == "ft" ? "feet" : "inches")")
    }

    private var trainingFields: some View {
        ProfilePickerRow(label: "Experience level", footnote: experience.description) {
            Picker("Experience", selection: $experience) {
                ForEach(ExperienceLevel.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(.ember)
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            Text("Save Changes")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.ember)
                .cornerRadius(14)
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }
}

struct ProfilePickerRow<Content: View>: View {
    let label: String
    var footnote: String?
    @ViewBuilder var content: Content

    init(label: String, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
                Spacer()
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.surface)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.borderColor, lineWidth: 1))

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 2)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textSecondary)

            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .padding(14)
                .background(Color.surface)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.borderColor, lineWidth: 1))
                .keyboardType(keyboardType)
        }
    }
}
