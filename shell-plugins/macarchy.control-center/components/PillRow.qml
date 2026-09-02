pragma ComponentBehavior: Bound

// A mutually-exclusive row of chips — qs.Ui's ButtonGroup with the one change
// that matters on this theme.
//
// ButtonGroup paints the chosen chip with Button's `selected`, and `selected`
// recolours the LABEL to an accent-derived colour ON TOP of the accent fill:
// accent on accent, unreadable on apple-glass. `active` paints the same fill
// and leaves the label in the foreground colour, which is what we want.
//
// Chips take their natural width inside a Row, so a group never comes out
// ragged the way a RowLayout of fillWidth buttons does with uneven labels.

import QtQuick
import qs.Commons
import qs.Ui

Row {
  id: root

  // Either a plain string[] (label == value) or [{ value, label }].
  property var options: []
  property string value: ""
  property color foreground: Color.popups.text
  property real fontSize: Style.font.caption

  signal changed(string value)

  function optionValue(o) { return typeof o === "string" ? o : String(o.value) }
  function optionLabel(o) { return typeof o === "string" ? o : String(o.label) }

  spacing: Style.space(4)

  Repeater {
    model: root.options

    delegate: Button {
      id: chip
      required property var modelData

      text: root.optionLabel(chip.modelData)
      active: root.optionValue(chip.modelData) === root.value
      bordered: true
      foreground: root.foreground
      fontSize: root.fontSize
      onClicked: root.changed(root.optionValue(chip.modelData))
    }
  }
}
