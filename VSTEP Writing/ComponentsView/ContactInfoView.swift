import SwiftUI

struct ContactInfoView: View {
    var body: some View {
        ScrollView{
            logoSection
                .padding()
            appInfoFooter
                .padding()
            ContactLists
                .padding()
        }
        .navigationTitle("Contact us")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }
    
    private var logoSection: some View {
        VStack(spacing: 0) {
            Image(systemName: "graduationcap")
                .font(.system(size: 120))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
            
            Text("VSTEP Writing")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 20)
        }
    }
    
    private var appInfoFooter: some View {
        VStack(spacing: 6) {
            Text("Powered by Vinhhaphoi from NTHT × Vinhhaphoi")
                .font(.caption)
                .foregroundStyle(.primary)

            Text("© 2026 All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
    
    private var ContactLists: some View {
        VStack(spacing: 0) {
            ForEach(Array(contactList.enumerated()), id: \.offset) { index, contactItem in
                Button {
                    handleContactAction(contactItem)
                } label: {
                    HStack(spacing: 15) {
                        Image(systemName: contactItem.icon)
                            .font(.system(size: 24))
                            .foregroundStyle(contactItem.iconColor)
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(contactItem.title)
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(.primary)
                            
                            Text(contactItem.value)
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                        
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.plain)

                if index != contactList.count - 1 {
                    Divider()
                        .padding(.leading, 70)
                }
            }
        }
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    private var contactList: [ContactInfo] {
        return [
            ContactInfo(
                icon: "envelope.front",
                iconColor: .blue,
                title: "Email",
                value: "support@vinhhaphoi.com",
                action: .email
            ),
            ContactInfo(
                icon: "globe",
                iconColor: .green,
                title: "Website",
                value: "vinhhaphoi.com",
                action: .website
            ),
            ContactInfo(
                icon: "phone.fill",
                iconColor: .orange,
                title: "Phone",
                value: "+84 845 655 779",
                action: .phone
            ),
        ]
    }
    
    private func handleContactAction(_ contact: ContactInfo) {
        switch contact.action {
        case .email:
            if let url = URL(string: "mailto:\(contact.value)") {
                UIApplication.shared.open(url)
            }
        case .website:
            if let url = URL(string: "https://\(contact.value)") {
                UIApplication.shared.open(url)
            }
        case .phone:
            let phone = contact.value.replacingOccurrences(of: " ", with: "")
            if let url = URL(string: "tel:\(phone)") {
                UIApplication.shared.open(url)
            }
        }
    }
}

struct ContactInfo {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let action: ContactAction
}

enum ContactAction {
    case email
    case website
    case phone
}
