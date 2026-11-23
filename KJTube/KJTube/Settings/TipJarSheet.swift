import SwiftUI

/// The small sheet behind "Buy KJ a coffee" in Settings (docs/specs/tip-jar.md).
struct TipJarSheet: View {
    @State private var model = TipJarModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Buy KJ a coffee")
                .font(.title2.bold())
            Text("KJ Tube is free and stays free. A tip is just a thank-you and unlocks nothing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            content
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .presentationDetents([.medium])
        .task { await model.load() }
        .task(id: model.closesSoon) {
            guard model.closesSoon else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { dismiss() }
        }
        .sensoryFeedback(.success, trigger: model.phase) { _, new in new == .thanks }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().padding(.top, 24)
        case .unavailable:
            note(TipJarModel.unavailableText)
        case .thanks:
            Text(TipJarModel.thanksText).font(.title.bold()).padding(.top, 24)
        case .waitingForApproval:
            note(TipJarModel.waitingText)
        case .ready(let failed):
            if failed {
                Text(TipJarModel.failedText)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            buttons.disabled(false)
        case .buying:
            buttons.disabled(true)
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            ForEach(model.tips) { tip in
                Button {
                    Task { await model.buy(tip) }
                } label: {
                    HStack {
                        Text(tip.name).multilineTextAlignment(.leading)
                        Spacer()
                        Text(tip.price).monospacedDigit()
                    }
                    .font(.body.weight(.semibold))
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 24)
    }
}
