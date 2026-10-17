import SwiftUI

/// The phone address and a small QR code for it, at the right end of the ticker, so phones can
/// open the queue page mid-song. Says "No network" while the TV has no address.
struct PhoneQRBadge: View {
    @State private var phoneURL = LocalAddress.phoneURL()
    /// Made only when the address changes, not on every redraw of the player screen.
    @State private var qr = LocalAddress.phoneURL().flatMap(QRCode.image(for:))

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .trailing, spacing: 4) {
                Text("ADD SONGS").font(.system(size: 22, weight: .bold)).kerning(3).foregroundStyle(Theme.pink)
                Text(phoneURL ?? "No network").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.orange)
                    .lineLimit(1).fixedSize()
            }
            if let qr {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 112, height: 112)
                    .padding(8)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("QR code for \(phoneURL ?? "")")
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: IdleView.addressRefresh)
                let url = LocalAddress.phoneURL()
                if url != phoneURL {
                    phoneURL = url
                    qr = url.flatMap(QRCode.image(for:))
                }
            }
        }
    }
}
