import SwiftData
import SwiftUI

/// Port of /qaza: missed-prayer balances.
struct QazaView: View {
    @Query private var rows: [Qaza]

    var body: some View {
        let balances = Dictionary(rows.map { ($0.prayerName, $0.remaining) }, uniquingKeysWith: { a, _ in a })
        let total = Prayers.qaza.reduce(0) { $0 + (balances[$1] ?? 0) }

        NavigationStack {
            List {
                Section {
                    LabeledContent("Total remaining") {
                        Text("\(total)").font(.title2.bold().monospacedDigit()).foregroundStyle(.primary)
                    }
                } footer: {
                    Text("Tap a prayer to add to your count (+) or record make-ups (−).")
                }
                Section {
                    ForEach(Prayers.qaza, id: \.self) { name in
                        NavigationLink(value: name) {
                            LabeledContent(name, value: "\(balances[name] ?? 0)")
                                .monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Qaza")
            .navigationDestination(for: String.self) { QazaDetailView(name: $0) }
        }
    }
}

struct QazaDetailView: View {
    @Environment(AppModel.self) private var model
    @Query private var rows: [Qaza]
    let name: String

    private let deltas = [[-10, -5, -1], [1, 10, 50]]

    var body: some View {
        let remaining = rows.first { $0.prayerName == name }?.remaining ?? 0
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("\(remaining)")
                    .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(value: Double(remaining)))
                Text("remaining").foregroundStyle(.secondary)
            }
            .padding(.top, 32)

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(deltas, id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { delta in
                            Button {
                                withAnimation { _ = model.logs.adjustQaza(name, by: delta) }
                            } label: {
                                Text(delta < 0 ? "−\(-delta)" : "+\(delta)")
                                    .font(.title3.bold().monospacedDigit())
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .tint(delta < 0 ? .green : .accentColor)
                            .disabled(delta < 0 && remaining == 0)
                            .accessibilityLabel(delta < 0 ? "Record \(-delta) made up" : "Add \(delta) missed")
                        }
                    }
                }
            }
            .padding(.horizontal)
            .sensoryFeedback(.increase, trigger: remaining)

            Text("− records make-ups, + adds to your count.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
