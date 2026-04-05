<div align="center">

<img src="icon.svg" width="128" />

# Kommit

Opinionated Mac app for planning life.

[![Download](https://img.shields.io/badge/Download-Latest%20Release-blue?style=for-the-badge)](https://github.com/razeghi71/kommit/releases/latest/download/Kommit.zip)

</div>

## Overview

Kommit is an app for planning two things: what you need to get done, and how money comes in and goes out. **Tasks** is an infinite canvas for mapping that work as nodes linked by dependency arrows. **Finances** is where you plan recurring money, log transactions, and watch cash flow on a calendar.

## Task board

### Visual Task Mapping

Double-click anywhere on the infinite canvas to create a task node. Pan with two fingers, pinch to zoom, and hit **⌘0** whenever you need to snap back to everything at once.

### Dependency Arrows

Hover any task and you'll see four **+** buttons on each side. Drag from a **+** button to an existing task to draw an arrow connecting the two. The arrow means the source task has to be done before the target task can start. You can also click a **+** button without dragging to quickly spawn a new task in that direction, or drag from a **+** onto empty space to place a new task at that spot. Select an arrow and press Delete to remove a connection.

### Planned Dates & Budgets

Right-click a task to set a target date or a budget. Hover a task with a date to see it as a tooltip. Dates and budgets show up in the context menu so you can change or remove them anytime.

### Task Statuses

Mark tasks with colored statuses like "In Progress" or "Done" from the right-click menu. Customize the full status palette under Settings (**⌘,**), picking your own names and colors. Each task's border reflects its current status so you can scan the canvas at a glance.

### Search

Press **⌘F** to find tasks by name. Step through matches with the arrow buttons or Enter. The canvas scrolls to each result so nothing stays hidden.

### Alignment & Snapping

While you drag a task, it softly snaps to other tasks’ edges and centers. **Alignment guides**—red vertical and horizontal lines plus small snap markers at the joints—show what you’re lining up with, similar to layout rulers in design tools. To align several tasks in one step, select them, right-click, open **Align**, and pick **Align Left**, **Align Right**, **Align Top**, **Align Bottom**, **Align Horizontal Center**, or **Align Vertical Center**.

### Hide & Unhide

Right-click a task and choose **Hide** to tuck it away. Toggle **Show Hidden Items** in the View menu when you need to bring hidden tasks back with a dashed border. Great for clearing completed work off the canvas without losing it.

### Depth Ranks

Turn on **Show Node Ranks** in the View menu to display small rank badges on each task. Tasks with no dependencies get rank 0, their direct dependents get rank 1, and so on, giving you a quick sense of how many steps are in a chain.

### Multi-Select

Shift-click to toggle individual tasks in your selection. Click on empty space and drag to draw a selection rectangle around a group. Move, re-status, set dates, hide, or delete the whole group at once.

### Undo / Redo

Every change is snapshotted. **⌘Z** to undo, **⌘⇧Z** to redo, up to 50 levels deep.

## Finances

Open the **Finances** tab to manage money alongside your graph. The left sidebar switches between four areas.

### Financial planning

**Commitments** are recurring income or expenses you expect on a schedule (rent, salary, subscriptions, and similar). They generate **due occurrences** you can mark as paid. **Forecasts** are softer recurring estimates—think groceries or discretionary spending—shown in the calendar as projections, not as items you "pay off" like commitments.

Add items from the **+** menu. Commitments and forecasts support income vs expense, recurrence, tags, and can be paused. By default, commitments that are fully paid through the past are hidden; turn **Hide fully paid commitments** off under Settings (**⌘,**) → **Financial** if you want them listed anyway.

### Transactions

A month-scoped ledger of financial events. Add recorded spending or income, attribute recorded transactions to forecasts, defer them to later bill commitments, or log settlement transactions that clear commitment occurrences. Rows show those planning links directly, and you can attach tags and notes.

### Calendar

A horizontal, day-by-day view that rolls from recent history into the next several months. Each column lists commitment due items and forecast projections; paid commitments show as settled, and overdue unpaid items roll forward visually. Set a **starting balance** (cash at the start of today) to project **end-of-day balances** forward; totals summarize money in, money out, and the running balance.

For an unpaid commitment on a day, use the **+** control on the card to **record** a transaction—on the due date, on today, on the first working day on or after the due date, or a custom date.

### Summary

Pick a month to see **income, expenses, and net** for recorded transactions, **spending by tag** (expenses allocated across tags), and **forecast vs actual** bars comparing what recurring forecasts expected for that month to the recorded transactions you attributed to those forecasts. Settlement transactions do not double-count spending there.

## Save & Open

**⌘S** saves your board as a JSON file. **⌘O** opens one. The app warns before discarding unsaved changes. Older Kommit (and legacy Domino) JSON files are loaded and migrated automatically.

## Requirements

- macOS 14+
- Swift 6.0+

## Build & Run

Run directly from source:

```
swift run Kommit
```

## Install as macOS App

Bundle it into a proper `.app`:

```
./scripts/bundle.sh
```

This builds a release binary and creates `build/Kommit.app`. To install:

```
cp -R build/Kommit.app /Applications/
```

The app is unsigned, so on first launch you may need to right-click > Open (or allow it in System Settings > Privacy & Security).
