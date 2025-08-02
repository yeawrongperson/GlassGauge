
import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $state.selection) {
                Section("General") {
                    Label("Overview", systemImage: "rectangle.3.group").tag(SectionID.overview)
                    Label("Sensors", systemImage: "dot.radiowaves.left.and.right").tag(SectionID.sensors)
                    Label("Alerts", systemImage: "bell.badge").tag(SectionID.alerts)
                    Label("Logs", systemImage: "doc.append").tag(SectionID.logs)
                }
                Section("System") {
                    Label("CPU", systemImage: "cpu").tag(SectionID.cpu)
                    Label("GPU", systemImage: "rectangle.portrait.on.rectangle.portrait.angled").tag(SectionID.gpu)
                    Label("Memory", systemImage: "memorychip").tag(SectionID.memory)
                    Label("Disks", systemImage: "externaldrive").tag(SectionID.disks)
                    Label("Network", systemImage: "wifi").tag(SectionID.network)
                    Label("Battery", systemImage: "battery.100").tag(SectionID.battery)
                    Label("Fans", systemImage: "fanblades").tag(SectionID.fans)
                    Label("Power", systemImage: "bolt.fill").tag(SectionID.power)
                }
                Section("App") {
                    Label("Settings", systemImage: "gearshape").tag(SectionID.settings)
                }
            }
            .navigationTitle("GlassGauge")
        } detail: {
            switch state.selection {
            case .overview: OverviewView().environmentObject(state)
            case .sensors: SensorsView().environmentObject(state)
            case .alerts: AlertsView().environmentObject(state)
            case .logs: LogsView().environmentObject(state)
            case .cpu: SensorDetailView(metric: state.cpu)
            case .gpu: SensorDetailView(metric: state.gpu)
            case .memory: SensorDetailView(metric: state.memory)
            case .disks: SensorDetailView(metric: state.disk)
            case .network: SensorDetailView(metric: state.network)
            case .battery: SensorDetailView(metric: state.battery)
            case .fans: SensorDetailView(metric: state.fans)
            case .power: SensorDetailView(metric: state.power)
            case .settings: SettingsView().environmentObject(state)
            }
        }
        .background(VisualEffectView(material: .hudWindow))
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Picker("Range", selection: $state.range) {
                    Text("Now").tag(TimeRange.now)
                    Text("1h").tag(TimeRange.hour1)
                    Text("24h").tag(TimeRange.hour24)
                }
                .pickerStyle(.segmented)

                Spacer()

                TextField("Search sensors…", text: $state.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
            }
        }
    }
}
