import SwiftUI

struct SponsorBlockSettingsView: View {
    @State private var options = UserDefaults.sponsorBlockOptions

    var body: some View {
        List {
            Section(footer: Text("Skips community-marked segments in podcasts.")) {
                Toggle("Enable SponsorBlock", isOn: $options.enabled)
                Toggle("Show colored overlay on progress bar", isOn: $options.showOverlay)
                    .disabled(!options.enabled)
                Toggle("Show toast when skipping", isOn: $options.showToast)
                    .disabled(!options.enabled)
                Toggle("Respect manual seek (don't re-skip)", isOn: $options.respectManualSeek)
                    .disabled(!options.enabled)
                Toggle("Log only (don't seek)", isOn: $options.logOnly)
                    .disabled(!options.enabled)
            }

            Section(header: Text("Categories")) {
                ForEach(SponsorBlockOptions.allCategoryOrder, id: \.self) { key in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(prettyName(key))
                                .font(.body)
                            Spacer()
                            ColorPicker("", selection: bindingForColor(key), supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 32)
                                .disabled(!options.enabled)
                        }
                        Picker("", selection: bindingForAction(key)) {
                            ForEach(SponsorBlockAction.allCases, id: \.self) { act in
                                Text(actionLabel(act)).tag(act)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .disabled(!options.enabled)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section(header: Text("Reporting (WIP)"),
                    footer: Text("Submit + vote on segments. Coming soon.")) {
                Text("Vote segment up/down")
                    .foregroundColor(.gray)
                Text("Submit new segment")
                    .foregroundColor(.gray)
            }
            .disabled(true)

            Section(header: Text("Advanced")) {
                HStack {
                    Text("Server")
                    Spacer()
                    TextField("https://sponsor.ajay.app", text: $options.serverURL)
                        .multilineTextAlignment(.trailing)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                }
                Stepper(
                    "Min duration: \(String(format: "%.1f", options.minSegmentDuration))s",
                    value: $options.minSegmentDuration,
                    in: 0.0...30.0,
                    step: 0.5
                )
                .disabled(!options.enabled)
            }

            Section(header: Text("Credits"),
                    footer: Text("Segment data from the SponsorBlock community (sponsor.ajay.app). Integration ported from Spot-SponsorBlock-Extension by Spot-SponsorBlock.")) {
                Link("Spot-SponsorBlock-Extension on GitHub",
                     destination: URL(string: "https://github.com/Spot-SponsorBlock/Spot-SponsorBlock-Extension")!)
                Link("SponsorBlock", destination: URL(string: "https://sponsor.ajay.app")!)
            }

            Section {
                Button {
                    options = SponsorBlockOptions(
                        enabled: options.enabled,
                        logOnly: false,
                        showOverlay: true,
                        showToast: false,
                        respectManualSeek: false,
                        serverURL: "https://sponsor.ajay.app",
                        minSegmentDuration: 1.0,
                        categories: SponsorBlockOptions.defaultCategories,
                        colors: SponsorBlockOptions.defaultColors
                    )
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset to defaults")
                    }
                    .foregroundColor(.red)
                }
            }

            Section {
                Color.clear
                    .frame(height: 90)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(GroupedListStyle())
        .animation(.default, value: options)
        .onChange(of: options) { newValue in
            UserDefaults.sponsorBlockOptions = newValue
            NotificationCenter.default.post(name: SponsorBlockSkipper.segmentsChangedNotification, object: nil)
        }
    }

    private func bindingForAction(_ key: String) -> Binding<SponsorBlockAction> {
        Binding(
            get: { options.categories[key] ?? .disabled },
            set: { options.categories[key] = $0 }
        )
    }

    private func bindingForColor(_ key: String) -> Binding<Color> {
        Binding(
            get: { Color(hex: options.color(for: key)) },
            set: { newColor in options.colors[key] = "#" + newColor.hexString }
        )
    }

    private func actionLabel(_ a: SponsorBlockAction) -> String {
        switch a {
        case .disabled:   return "Off"
        case .showOnly:   return "Show"
        case .manualSkip: return "Manual"
        case .autoSkip:   return "Auto"
        }
    }

    private func prettyName(_ key: String) -> String {
        switch key {
        case "sponsor":          return "Sponsor"
        case "selfpromo":        return "Unpaid/Self Promotion"
        case "interaction":      return "Interaction Reminder"
        case "intro":            return "Intermission/Intro"
        case "outro":            return "Outro/Credits"
        case "preview":          return "Preview/Recap"
        case "hook":             return "Hook/Greetings"
        case "filler":           return "Tangent/Filler"
        case "exclusive_access": return "Exclusive Access"
        default:                 return key
        }
    }
}
