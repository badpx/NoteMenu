// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoteMenuEditor",
    platforms: [.macOS(.v13)],
    products: [.library(name: "NoteMenuEditor", targets: ["NoteMenuEditor"])],
    targets: [
        .target(name: "NoteMenuEditor", path: "NoteMenu", exclude: ["Views", "Resources", "AppDelegate.swift", "PanelController.swift", "NoteMenuApp.swift"], sources: ["Editor", "Notes"]),
        .testTarget(name: "NoteMenuEditorTests", dependencies: ["NoteMenuEditor"], path: "Tests/NoteMenuEditorTests"),
    ]
)
