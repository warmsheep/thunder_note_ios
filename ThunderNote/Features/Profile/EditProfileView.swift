import SwiftUI
import PhotosUI
import UIKit

/// D2-I6-05 编辑资料独立全屏页。
///
/// 与 Android `EditProfileFragment` 行为对齐：
/// - 字段：昵称（≤32 字符）、简介（≤200 字符）；
/// - 头像入口：弹底部菜单「从相册选择 / 选择 emoji」，对齐 Android `AlertDialog`；
/// - 「保存」走 `PUT /api/users/profile`，成功后回写 ProfileViewModel 缓存。
struct EditProfileView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @ObservedObject var viewModel: ProfileViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var nickname: String = ""
    @State private var bio: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    // 头像菜单 / 各 sheet 状态
    @State private var showAvatarMenu: Bool = false
    @State private var showEmojiPicker: Bool = false
    @StateObject private var photoPickerHelper = PhotosPickerHelper()
    @State private var croppingImage: UIImage? = nil

    private static let nicknameMax = 32
    private static let bioMax = 200

    var body: some View {
        Form {
            avatarSection
            nicknameSection
            bioSection
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Color.red)
                        .font(.system(size: 13))
                }
            }
        }
        .navigationTitle("编辑资料")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    Task { await save() }
                }
                .disabled(isSaving)
                .accessibilityIdentifier("editProfileSave")
            }
        }
        .onAppear {
            let p = viewModel.profile
            nickname = p?.nickname ?? ""
            bio = p?.bio ?? ""
        }
        .confirmationDialog("更换头像", isPresented: $showAvatarMenu, titleVisibility: .visible) {
            Button("从相册选择") {
                photoPickerHelper.reset()
                showPhotosPicker = true
            }
            Button("选择 emoji") {
                showEmojiPicker = true
            }
            Button("取消", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $photoPickerHelper.selectedItem,
            matching: .images
        )
        .onChange(of: photoPickerHelper.selectedItem) { newItem in
            guard newItem != nil else { return }
            Task { @MainActor in
                if let url = await photoPickerHelper.loadLocalURL(suggestedExtension: "jpg"),
                   let data = try? Data(contentsOf: url),
                   let image = UIImage(data: data) {
                    croppingImage = image
                }
            }
        }
        .sheet(isPresented: $showEmojiPicker) {
            AvatarEmojiPickerView(initialEmoji: viewModel.profile?.avatar) { emoji in
                Task { await viewModel.updateAvatar(emoji) }
            }
        }
        .fullScreenCover(item: Binding(
            get: { croppingImage.map { CroppingImageBox(image: $0) } },
            set: { croppingImage = $0?.image }
        )) { box in
            AvatarCropView(source: box.image) { jpegData in
                Task { await viewModel.updateAvatarFromImageData(jpegData) }
            }
        }
    }

    @State private var showPhotosPicker: Bool = false

    // MARK: - sections

    private var avatarSection: some View {
        Section {
            HStack(spacing: DesignTokens.Spacing.medium) {
                avatarPreview
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .background(Circle().fill(DesignTokens.Color.surface))
                Button("更换头像") {
                    showAvatarMenu = true
                }
                .accessibilityIdentifier("editProfileChangeAvatar")
                Spacer()
            }
            .padding(.vertical, 4)
        } header: {
            Text("头像")
        }
    }

    private var nicknameSection: some View {
        Section {
            TextField("昵称", text: $nickname)
                .accessibilityIdentifier("editProfileNickname")
                .onChange(of: nickname) { newValue in
                    if newValue.count > Self.nicknameMax {
                        nickname = String(newValue.prefix(Self.nicknameMax))
                    }
                }
        } header: {
            Text("昵称")
        } footer: {
            Text("\(nickname.count) / \(Self.nicknameMax)")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.Color.textSecondary)
        }
    }

    private var bioSection: some View {
        Section {
            TextField("简介", text: $bio, axis: .vertical)
                .lineLimit(3...6)
                .accessibilityIdentifier("editProfileBio")
                .onChange(of: bio) { newValue in
                    if newValue.count > Self.bioMax {
                        bio = String(newValue.prefix(Self.bioMax))
                    }
                }
        } header: {
            Text("简介")
        } footer: {
            Text("\(bio.count) / \(Self.bioMax)")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.Color.textSecondary)
        }
    }

    @ViewBuilder
    private var avatarPreview: some View {
        let avatar = viewModel.profile?.avatar
        if let avatar, isEmoji(avatar) {
            Text(avatar)
                .font(.system(size: 40))
                .frame(width: 64, height: 64)
        } else if let localImage = AvatarLocalCache.loadImage() {
            Image(uiImage: localImage)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
        } else if let avatar,
                  let url = dependencies.mediaUrlResolver.resolve(avatar) {
            AuthenticatedAsyncImage(
                url: url,
                loader: dependencies.authenticatedImageLoader,
                content: { image in
                    image.resizable().scaledToFill()
                },
                placeholder: {
                    Text("😊").font(.system(size: 40))
                }
            )
            .frame(width: 64, height: 64)
        } else {
            Text("😊").font(.system(size: 40))
        }
    }

    private func isEmoji(_ avatar: String) -> Bool {
        !avatar.isEmpty && !avatar.hasPrefix("http") && !avatar.contains("/") && avatar.count <= 4
    }

    // MARK: - save

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        let trimmedNick = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNick.count > Self.nicknameMax {
            errorMessage = "昵称不能超过 \(Self.nicknameMax) 字符"
            return
        }
        if trimmedBio.count > Self.bioMax {
            errorMessage = "简介不能超过 \(Self.bioMax) 字符"
            return
        }
        var next = viewModel.profile ?? UserProfile()
        next.nickname = trimmedNick.isEmpty ? nil : trimmedNick
        next.bio = trimmedBio.isEmpty ? nil : trimmedBio
        do {
            let updated = try await dependencies.userRepository.updateProfile(next)
            viewModel.applyUpdated(updated)
            dismiss()
        } catch let api as APIError {
            errorMessage = api.displayMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// `fullScreenCover(item:)` 要求 Identifiable；UIImage 不是，所以装一层。
private struct CroppingImageBox: Identifiable {
    let id = UUID()
    let image: UIImage
}
