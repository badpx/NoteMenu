// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoteMenuEditor",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.library(name: "NoteMenuEditor", targets: ["NoteMenuEditor"])],
    targets: [
        .target(name: "NoteMenuEditor", path: "NoteMenu", exclude: ["Views", "Resources", "AppDelegate.swift", "PanelController.swift", "NoteMenuApp.swift"], sources: ["Editor", "Notes"], resources: [.process("Localization")]),
        .testTarget(name: "NoteMenuEditorTests", dependencies: ["NoteMenuEditor"], path: "Tests/NoteMenuEditorTests"),
    ]
)
