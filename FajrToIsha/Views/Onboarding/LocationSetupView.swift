import SwiftUI

/// Location step shared by onboarding and "Change Location".
/// Uses CoreLocation, or a manual city when location is denied.
struct LocationSetupView: View {
    @Environment(AppModel.self) private var model
    let onResolved: (ResolvedTimings) -> Void

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showCityForm = false
    @State private var city = ""
    @State private var country = ""

    var body: some View {
        VStack(spacing: 16) {
            Button {
                Task { await useCurrentLocation() }
            } label: {
                Label("Use my current location", systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking)

            if showCityForm {
                VStack(spacing: 10) {
                    TextField("City (e.g. Tashkent)", text: $city)
                        .textContentType(.addressCity)
                    TextField("Country (e.g. Uzbekistan)", text: $country)
                        .textContentType(.countryName)
                    Button {
                        Task { await useCity() }
                    } label: {
                        Text("Look up city").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isWorking || city.trimmed.isEmpty || country.trimmed.isEmpty)
                }
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit { Task { await useCity() } }
            } else {
                Button("Enter a city instead") { withAnimation { showCityForm = true } }
                    .disabled(isWorking)
            }

            if isWorking {
                ProgressView("Calculating your timezone and prayer schedules...")
                    .font(.footnote)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func useCurrentLocation() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let coordinate = try await model.location.requestCoordinate()
            let resolved = try await model.setLocation(.coordinates(latitude: coordinate.latitude,
                                                                    longitude: coordinate.longitude))
            onResolved(resolved)
        } catch let error as LocationManager.LocationError {
            errorMessage = error.localizedDescription
            withAnimation { showCityForm = true }
        } catch {
            errorMessage = "Failed to calculate your timezone. Please try again later.\n\(error.localizedDescription)"
        }
    }

    private func useCity() async {
        let c = city.trimmed, k = country.trimmed
        guard !c.isEmpty, !k.isEmpty, !isWorking else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            onResolved(try await model.setLocation(.city(name: c, country: k)))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Port of the bot's "Location registered successfully!" message.
struct LocationResultView: View {
    let resolved: ResolvedTimings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Location registered successfully!", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Color.accentColor)
            LabeledContent("Timezone", value: resolved.timeZone.identifier)
            Divider()
            Text("Today's Timings").font(.subheadline.weight(.semibold))
            ForEach(Prayers.timingNames, id: \.self) { name in
                LabeledContent(name, value: TimeOfDay.format(resolved.timings[name] ?? "--:--"))
                    .font(.body.monospacedDigit())
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Sheet for Settings > Change Location.
struct ChangeLocationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var resolved: ResolvedTimings?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Share your new location to update your timezone and prayer times. "
                         + "Your settings and logged prayers are kept.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if let resolved {
                        LocationResultView(resolved: resolved)
                        Button("Done") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    } else {
                        LocationSetupView { result in
                            resolved = result
                            Task { await model.refresh() }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Change Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
