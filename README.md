<div align="center">

<img src="icon.svg" width="128" />

# Domino

Plan projects and life on your Mac in one place. Domino lays out goals and tasks on an open canvas, adds dates and budgets where you need them, and offers a table view when a list is easier than a map. Built with SwiftUI.

[![Download](https://img.shields.io/badge/Download-Latest%20Release-blue?style=for-the-badge)](https://github.com/razeghi71/domino/releases/latest/download/Domino.zip)

![Screenshot](screenshot.png)

</div>

## Features

- **Graph canvas** — infinite pan and zoom (zoom follows the pointer); nodes link in a hierarchy you can reshape
- **Table view** — the same map as rows: text, planned date, budget, color, and visibility
- **Planned dates** and **budgets** on nodes
- **Hide nodes**; **Show Hidden Items** in the menu when you need hidden work back on the canvas
- **Search** across node text (**⌘F**)
- **Recenter canvas** after heavy zoom or pan (**⌘0**)
- **Snapping** — alignment guides, equal-spacing gap guides, and align selected nodes to a shared left, right, top, or bottom edge
- **Node colors** (presets or custom)
- **Depth ranks** from root nodes (optional via the menu)
- **Undo/redo** and **save/open** documents as JSON

## Requirements

- macOS 14+
- Swift 6.0+

## Build & Run

Run directly from source:

```
swift run Domino
```

## Install as macOS App

Bundle it into a proper `.app`:

```
./scripts/bundle.sh
```

This builds a release binary and creates `build/Domino.app`. To install:

```
cp -R build/Domino.app /Applications/
```

The app is unsigned, so on first launch you may need to right-click > Open (or allow it in System Settings > Privacy & Security).
