import SwiftUI

struct MenuBarLabelView: View {
    let snapshot: ServiceSnapshot

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: snapshot.staleCount > 0 ? "exclamationmark.circle.fill" : "bolt.circle")
            Text("\(snapshot.visibleDevServices.count)")
            if snapshot.staleCount > 0 {
                Text("!\(snapshot.staleCount)")
            }
        }
        .help("What's Live")
    }
}
