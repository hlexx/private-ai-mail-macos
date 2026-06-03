import DesignSystem
import SwiftUI

struct KeyboardSettingsTab: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                    .foregroundStyle(Color.rbFg1)

                KeyboardCatalogList()

                Divider()
                    .background(Color.rbStroke2)

                Text("Customisable shortcuts coming in a future release. Open an issue to request specific bindings.")
                    .font(.callout)
                    .foregroundStyle(Color.rbFg3)
            }
            .padding(24)
        }
        .background(Color.rbBgCanvas)
    }
}
