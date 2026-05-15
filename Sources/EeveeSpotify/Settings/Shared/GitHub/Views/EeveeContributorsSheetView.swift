import SwiftUI

// Mod4 avatar embedded as base64 JPEG (200x200)
private let mod4AvatarBase64 = "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"

private let mod4Contributor = EeveeContributor(
    username: "Mod4",
    roles: ["Collaborator", "Developer"]
)

struct ContributorRow: View {
    let contributor: EeveeContributor
    
    var body: some View {
        HStack {
            avatarView
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(contributor.username)
                    .font(.headline)
                
                Text(contributor.roles.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var avatarView: some View {
        if contributor.username == "Mod4",
           let data = Data(base64Encoded: mod4AvatarBase64),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
        } else {
            ImageView(urlString: "https://github.com/\(contributor.username).png")
        }
    }
}

struct EeveeContributorsSheetView: View {
    @State private var sections: [EeveeContributorSection] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            contentView
                .navigationTitle("contributors".localized)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Button {
                        WindowHelper.shared.dismissCurrentViewController()
                    } label: {
                        Text("Done".uiKitLocalized)
                            .font(.headline)
                    }
                }
                .onAppear {
                    loadContributors()
                }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if isLoading {
            ProgressView("Loading".uiKitLocalized)
        } else if sections.isEmpty {
            Text("No contributors found")
                .foregroundColor(.gray)
        } else {
            contributorsList
        }
    }
    
    private var sectionsWithMod4: [EeveeContributorSection] {
        guard !sections.isEmpty else { return sections }
        var result = sections
        // Inject Mod4 at the top of the first section
        result[0].contributors.insert(mod4Contributor, at: 2)
        return result
    }
    
    private var contributorsList: some View {
        List {
            ForEach(sectionsWithMod4, id: \.title) { section in
                Section(header: Text(section.title)) {
                    let contributors = section.shuffled ? section.contributors.shuffled() : section.contributors
                    ForEach(contributors, id: \.username) { contributor in
                        ContributorRow(contributor: contributor)
                    }
                }
            }
        }
    }
    
    private func loadContributors() {
        Task {
            do {
                sections = try await GitHubHelper.shared.getEeveeContributorSections()
            } catch {
                print("Failed to load contributors: \(error)")
            }
            isLoading = false
        }
    }
}
