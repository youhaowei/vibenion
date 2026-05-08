#if DEBUG
import Inject
#endif
import SwiftUI

struct SettingsView: View {
#if DEBUG
    @ObserveInjection var inject
#endif

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: .constant(false))
            Toggle("Play sound for approvals", isOn: .constant(true))
            Toggle("Show completed sessions", isOn: .constant(true))
        }
        .padding()
        .frame(width: 360)
#if DEBUG
        .enableInjection()
#endif
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView()
}
#endif
