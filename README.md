<div align="center">

<img src="icon.svg" width="128" />

# Domino

A lightweight mind map app for macOS, built with SwiftUI.

[![Download](https://img.shields.io/badge/Download-Latest%20Release-blue?style=for-the-badge)](https://github.com/razeghi71/domino/releases/latest/download/Domino.zip)

![Screenshot](screenshot.png)

</div>

## Features

- **Infinite canvas** with pan and pinch-to-zoom
- **Alignment guides & smart snapping** - drag nodes to see guide lines and snap to aligned positions with nearby nodes
- **Double-click** anywhere to create a node
- **Drag from edge handles** to create child nodes or connect existing nodes
- **Directed edges** with curved arrows between connected nodes
- **Click to select**, click again to edit text inline
- **Node colors** via right-click context menu (presets + custom color picker)
- **Undo/Redo** (Cmd+Z / Cmd+Shift+Z, up to 50 levels)
- **Save/Open** mind maps as JSON (Cmd+S, Cmd+O)
- **Delete** nodes or edges with the Delete key (children get reparented automatically)
- **Depth badges** showing each node's distance from root nodes

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
