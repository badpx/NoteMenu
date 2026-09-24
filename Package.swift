// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotesMateEditor",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.library(name: "NotesMateEditor", targets: ["NotesMateEditor"])],
    targets: [
        .target(name: "NotesMateEditor", path: "NotesMate", exclude: ["Views", "Resources", "AppDelegate.swift", "PanelController.swift", "NotesMateApp.swift"], sources: ["Editor", "Notes"], resources: [.process("Localization")]),
        .testTarget(name: "NotesMateEditorTests", dependencies: ["NotesMateEditor"], path: "Tests/NotesMateEditorTests"),
    ]
)
