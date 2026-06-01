import SwiftUI

struct NonIPadSpacerView: View {
    var body: some View {
        Spacer()
            .frame(height: UIDevice.current.isIpad ? 90 : 40)
            .listRowBackground(Color.clear)
            .modifier(ListRowSeparatorHidden())
    }
}
