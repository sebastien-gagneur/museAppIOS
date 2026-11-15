import SwiftUI

struct ChatView: View {
    @StateObject private var agent = AgentViewModel()
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let suggestions = [
        "Qu'est-ce que j'ai dans mon agenda demain ?",
        "Rappelle-moi d'appeler le garage vendredi à 9 h",
        "Trouve un bon restaurant italien près de la gare",
        "Prépare un mail pour décaler ma réunion de lundi",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if agent.items.isEmpty { emptyState }
                        ForEach(agent.items) { item in
                            row(item).id(item.id)
                        }
                        if agent.isRunning && agent.pendingApprovalID == nil {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Je m'en occupe…").foregroundStyle(.secondary)
                            }
                            .id("running")
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: agent.items.count) { _, _ in
                    if let id = agent.items.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { agent.reset() } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("Nouvelle conversation")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Que puis-je faire pour toi ?").font(.title2.bold())
            ForEach(suggestions, id: \.self) { s in
                Button { agent.send(s) } label: {
                    Text(s).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 24)
    }

    @ViewBuilder
    private func row(_ item: ChatItem) -> some View {
        switch item.kind {
        case .user(let text):
            HStack {
                Spacer(minLength: 40)
                Text(text)
                    .padding(12)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
            }
        case .assistant(let text):
            Text(markdown(text))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .activity(let text):
            Label(text, systemImage: "gearshape")
                .font(.footnote).foregroundStyle(.secondary)
        case .approval(let request):
            approvalCard(request, id: item.id)
        case .approvalResult(let title, let approved):
            Label("\(title) : \(approved ? "accepté" : "refusé")",
                  systemImage: approved ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(approved ? .green : .secondary)
        case .error(let text):
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private func approvalCard(_ request: ApprovalRequest, id: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(request.title, systemImage: "hand.raised.fill").font(.headline)
            Text(request.details)
            if agent.pendingApprovalID == id {
                HStack {
                    Button("Refuser", role: .cancel) { agent.resolveApproval(false) }
                        .buttonStyle(.bordered)
                    Button("Autoriser") { agent.resolveApproval(true) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Demande quelque chose…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            Button {
                agent.send(draft)
                draft = ""
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || agent.isRunning)
            .accessibilityLabel("Envoyer")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
