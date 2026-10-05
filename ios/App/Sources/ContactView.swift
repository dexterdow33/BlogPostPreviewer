import GSRKit
import GSRUI
import SwiftUI
import UIKit

/// Every way to reach the editor, safest first, as granitestatereport.com/tips/ lists them,
/// and what the app keeps on this phone.
struct ContactView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.openURL) private var openURL
    @State private var page: WebPage?
    @State private var copied: String?
    @State private var confirmWipe = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Signal is the best mix of safe and easy. Mail leaves the least digital trail. This app, the site's forms, and email are fine for anything you would not mind your employer seeing.")
                        .font(GSRTheme.serif(.subheadline))
                        .foregroundStyle(GSRTheme.ink)
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Signal").font(.headline).foregroundStyle(GSRTheme.navy)
                        Text(GSRContact.signalUsername).font(.system(.body, design: .monospaced))
                        Text("Messages are encrypted end to end, and you can set them to disappear. A username lets you reach the editor without handing over your phone number. Use a personal phone, never a work one.")
                            .font(.footnote).foregroundStyle(GSRTheme.ink2)
                    }
                    Button { copy(GSRContact.signalUsername, label: "Signal username") } label: {
                        Label("Copy the Signal username", systemImage: "doc.on.doc")
                    }
                    Button { page = WebPage(URL(string: "https://signal.org/")!) } label: {
                        Label("Get Signal (free, at signal.org)", systemImage: "arrow.down.circle")
                    }
                } header: {
                    Text("Signal: the best mix of safe and easy")
                }

                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(GSRContact.mailingAddress, id: \.self) { Text($0) }
                    }
                    .font(GSRTheme.serif(.body))
                    Text("Send copies, never the only original, with no return address, from a mailbox away from your home and your workplace.")
                        .font(.footnote).foregroundStyle(GSRTheme.ink2)
                    Button { copy(GSRContact.mailingAddress.joined(separator: "\n"), label: "Mailing address") } label: {
                        Label("Copy the mailing address", systemImage: "doc.on.doc")
                    }
                } header: {
                    Text("By mail: the least digital trail")
                }

                Section {
                    Button { openURL(GSRContact.phoneURL) } label: {
                        Label("Call \(GSRContact.phoneDisplay)", systemImage: "phone")
                    }
                    Button { openURL(GSRContact.emailURL) } label: {
                        Label("Email \(GSRContact.email)", systemImage: "envelope")
                    }
                } header: {
                    Text("Phone and email")
                } footer: {
                    Text("Say as little as you like on the first call. Email from a personal account; Google keeps a copy, and your address is attached.")
                }

                Section {
                    pageLink("How GSR handles what you send", GSRContact.tipsPage)
                    pageLink("Privacy Policy", GSRContact.privacyPolicy)
                    pageLink("Terms of Use", GSRContact.termsOfUse)
                    pageLink("Code of Ethics", GSRContact.codeOfEthics)
                } header: {
                    Text("Read first")
                }

                Section {
                    HStack {
                        Text("Unsent drafts on this phone")
                        Spacer()
                        Text("\(app.unsent.count)").foregroundStyle(GSRTheme.ink2)
                    }
                    Button("Delete everything the app is holding", role: .destructive) { confirmWipe = true }
                } header: {
                    Text("On this phone")
                } footer: {
                    Text("Drafts you have not sent stay inside the app until you send or delete them, and are left out of iCloud and computer backups. Anything sent is deleted from the phone as soon as the drop box confirms it. The app has no account and no ads, and runs no analytics of its own. Site pages opened in the app, like stories on the Latest tab, load the site's Google Analytics, as the Privacy Policy describes.")
                }

                Section {
                    Text("Granite State Report · Independent New Hampshire Journalism · Northfield, NH")
                        .font(.footnote)
                    Text("Version \(GSRApp.version)")
                        .font(.footnote).foregroundStyle(GSRTheme.ink3)
                }
            }
            .scrollContentBackground(.hidden)
            .background(GSRTheme.paper2.ignoresSafeArea())
            .navigationTitle("Contact")
            .sheet(item: $page) { p in SafariView(url: p.url).ignoresSafeArea() }
            .confirmationDialog("Delete every unsent draft and file the app is holding? Anything mid-send stops. This cannot be undone.",
                                isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { app.wipe() }
            }
            .overlay(alignment: .bottom) {
                if let copied {
                    Text("\(copied) copied")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(GSRTheme.navy))
                        .foregroundStyle(.white)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }
            }
        }
    }

    private func pageLink(_ title: String, _ url: URL) -> some View {
        Button { page = WebPage(url) } label: {
            Label(title, systemImage: "safari")
        }
    }

    private func copy(_ text: String, label: String) {
        UIPasteboard.general.string = text
        withAnimation { copied = label }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copied = nil }
        }
    }
}
