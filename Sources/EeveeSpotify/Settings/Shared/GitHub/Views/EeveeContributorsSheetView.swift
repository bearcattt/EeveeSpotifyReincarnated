import SwiftUI

struct ContributorRow: View {
    let contributor: EeveeContributor
    
    var body: some View {
        HStack {
            ImageView(urlString: "https://github.com/\(contributor.username).png")
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
    
    private var contributorsList: some View {
        List {
            ForEach(sections, id: \.title) { section in
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
