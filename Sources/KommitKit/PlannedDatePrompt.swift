import AppKit

@MainActor
func promptForPlannedDate(initialDate: Date?) -> Date? {
    let datePicker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 220, height: 160))
    datePicker.datePickerElements = .yearMonthDay
    datePicker.datePickerStyle = .clockAndCalendar
    datePicker.dateValue = initialDate ?? Date()

    let alert = NSAlert()
    alert.messageText = initialDate == nil ? "Set Planned Date" : "Change Planned Date"
    alert.informativeText = "Choose a planned date for this node."
    alert.accessoryView = datePicker
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")

    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    return datePicker.dateValue
}
