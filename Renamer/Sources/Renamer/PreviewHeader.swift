import SwiftUI

struct PreviewHeader: View {
    @EnvironmentObject private var session: RenameSession

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Podgląd zmian")
                    .font(.title2.weight(.semibold))
                Text("Pliki: \(session.items.count)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(PreviewSortKey.allCases) { key in
                    Button {
                        session.toggleSort(key)
                    } label: {
                        if session.sortKey == key {
                            Label(key.label, systemImage: session.sortAscending ? "arrow.up" : "arrow.down")
                        } else {
                            Text(key.label)
                        }
                    }
                }
            } label: {
                Label("Sortowanie", systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Sortuj podgląd. Kolejność nazw źródłowych wyznacza numerację.")
        }
        .padding(24)
    }
}
