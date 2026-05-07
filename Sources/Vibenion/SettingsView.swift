import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Toggle("Launch at login", isOn: .constant(false))
            Toggle("Play sound for approvals", isOn: .constant(true))
            Toggle("Show completed sessions", isOn: .constant(true))
        }
        .padding()
        .frame(width: 360)
    }
}
