import AppKit
import SwiftUI

struct AboutPane: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return short.map { "Version \($0)" } ?? "Development build"
    }

    // Resolves app/Sources/SharpFocus/Resources/github.svg at runtime.
    // Package.swift: resources: [.process("Resources")]  -> SharpFocus_SharpFocus.bundle/github.svg (SPM)
    // Xcode project: Resources build phase             -> Contents/Resources/github.svg (Bundle.main)
    private func loadGitHubImage() -> NSImage? {
        // 1. Xcode build - direct in main bundle
        if let url = Bundle.main.url(forResource: "github", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            return image
        }
        // 2. SPM build - nested .bundle
        if let bundleURL = Bundle.main.url(forResource: "SharpFocus_SharpFocus", withExtension: "bundle"),
           let bundle = Bundle(url: bundleURL),
           let url = bundle.url(forResource: "github", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            return image
        }
        // 3. SwiftPM Bundle.module (when built via `swift build`)
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "github", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            return image
        }
        #endif
        return nil
    }

    @ViewBuilder
    private var githubIcon: some View {
        if let image = loadGitHubImage() {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .frame(width: 16, height: 16)
        } else {
            // Fallback if resource missing - mirrors github.svg intent
            Image(systemName: "link")
                .frame(width: 16, height: 16)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
            Text("Sharp Focus").font(.title2.bold())
            Text(version).font(.callout).foregroundStyle(.secondary)
            Text("Focus on whats important. Deemphasize everything else.")
                .font(.body).foregroundStyle(.secondary)
                .padding(.top, 2)
            HStack(spacing: 22) {
                Label {
                    Link("GitHub", destination: URL(string: "https://github.com/ac40/sharpfocus")!)
                } icon: {
                    githubIcon
                }

                Label {
                    Link("Website", destination: URL(string: "https://acrichter.com")!)
                } icon: {
                    Image(systemName: "globe")
                        .font(.title3)
                }

                Label {
                    Link("Report an issue", destination: URL(string: "https://github.com/ac40/sharpfocus/issues")!)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3)
                }

            }
            .font(.callout)
            .padding(.top, 10)
            
            Spacer()
            Link("Support the Developer", destination: URL(string: "https://buymeacoffee.com/rn22w94kcqt")!)
                .padding(10)
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer()
            Text("Made by Aaron Richter · MIT License")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

