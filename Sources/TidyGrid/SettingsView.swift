import Combine
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            LayoutsTab()
                .tabItem { Label("Layouts", systemImage: "rectangle.split.2x2") }
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 660, height: 480)
    }
}

// MARK: - Layouts

private struct LayoutsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(settings.prefs.layouts) { layout in
                        HStack(spacing: 10) {
                            LayoutIcon(layout: layout).frame(width: 44, height: 28)
                            Text(layout.name.isEmpty ? "Untitled" : layout.name)
                        }
                        .padding(.vertical, 2)
                        .tag(layout.id)
                    }
                    .onMove { settings.prefs.layouts.move(fromOffsets: $0, toOffset: $1) }
                }
                Divider()
                HStack(spacing: 0) {
                    Button { add() } label: { Image(systemName: "plus").frame(width: 24, height: 20) }
                    Button { removeSelected() } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                        .disabled(selection == nil)
                    Spacer()
                    Button("Reset") { settings.prefs.layouts = GridLayout.defaults; selection = nil }
                        .controlSize(.small)
                        .padding(.trailing, 6)
                }
                .buttonStyle(.borderless)
                .padding(4)
            }
            .frame(width: 230)

            Divider()

            Group {
                if let i = settings.prefs.layouts.firstIndex(where: { $0.id == selection }) {
                    LayoutEditor(layout: $settings.prefs.layouts[i])
                        .id(settings.prefs.layouts[i].id)
                } else {
                    Text("Select a layout to edit it.\nDrag layouts in the list to change their order.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(20)
        }
    }

    private func add() {
        let layout = GridLayout(name: "New Layout", columns: 4, rows: 4, x: 1, y: 1, width: 2, height: 2)
        settings.prefs.layouts.append(layout)
        selection = layout.id
    }

    private func removeSelected() {
        guard let id = selection else { return }
        selection = nil
        settings.prefs.layouts.removeAll { $0.id == id }
    }
}

private struct LayoutEditor: View {
    @Binding var layout: GridLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Name", text: $layout.name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)

            HStack(spacing: 24) {
                Stepper("Columns: \(layout.columns)", value: gridBinding(\.columns), in: 1...12)
                Stepper("Rows: \(layout.rows)", value: gridBinding(\.rows), in: 1...12)
            }

            GridSelector(
                columns: layout.columns,
                rows: layout.rows,
                selection: Binding(get: { layout.rect }, set: { if let r = $0 { layout.rect = r } })
            )
            .aspectRatio(16 / 10, contentMode: .fit)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))

            Text("Drag across the grid to choose the part of the screen the window fills.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func gridBinding(_ key: WritableKeyPath<GridLayout, Int>) -> Binding<Int> {
        Binding(get: { layout[keyPath: key] }, set: {
            var l = layout
            l[keyPath: key] = $0
            layout = l.clamped()
        })
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var trusted = AX.isTrusted
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Permission") {
                if trusted {
                    Label("Accessibility access is on.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("TidyGrid needs Accessibility access to move and resize windows.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("Open Accessibility Settings…") {
                            AX.promptForTrust()
                            AX.openAccessibilitySettings()
                        }
                    }
                }
            }

            Section("Layout icons") {
                LabeledContent("Icon size") {
                    Slider(value: $settings.prefs.iconSize, in: 40...140, step: 4)
                }
                Picker("Position", selection: $settings.prefs.position) {
                    ForEach(PanelPosition.allCases) { Text($0.title).tag($0) }
                }
                Picker("Option key", selection: $settings.prefs.optionMode) {
                    ForEach(OptionKeyMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show where the window will go", isOn: $settings.prefs.showPreview)
            }

            Section("Quick Layout (⌃⌥Space)") {
                Stepper("Columns: \(settings.prefs.quickColumns)", value: $settings.prefs.quickColumns, in: 2...12)
                Stepper("Rows: \(settings.prefs.quickRows)", value: $settings.prefs.quickRows, in: 2...12)
            }

            Section("Keyboard") {
                Toggle("⌃⌥⌘1 to ⌃⌥⌘9 apply the first nine layouts to the active window",
                       isOn: $settings.prefs.layoutShortcuts)
            }

            Section {
                Toggle("Open TidyGrid at login", isOn: Binding(get: { openAtLogin }, set: { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        NSSound.beep()
                    }
                    openAtLogin = SMAppService.mainApp.status == .enabled
                }))
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in trusted = AX.isTrusted }
    }
}
