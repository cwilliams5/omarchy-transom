// Drag-to-reorder math shared by the taskbar and the tray (tests/run.js).

// Where a dragged button lands: its own index moved by however many slots
// the pointer travelled, kept within the row. (From Omarchy's dock.)
function dropIndex(fromIndex, offset, slotSize, count) {
  if (count <= 0 || !(slotSize > 0)) return fromIndex
  var target = fromIndex + Math.round(offset / slotSize)
  return Math.max(0, Math.min(count - 1, target))
}

// How far the button at index shifts while the one at from is dragged to
// drop: one slot toward the gap, if it's between them.
function dragShift(index, from, drop, slotSize) {
  if (from < 0 || index === from) return 0
  if (from < drop && index > from && index <= drop) return -slotSize
  if (from > drop && index < from && index >= drop) return slotSize
  return 0
}

// The list with the item at from moved to index to.
function moved(list, from, to) {
  var out = (list || []).slice()
  var item = out.splice(from, 1)[0]
  out.splice(Math.max(0, Math.min(out.length, to)), 0, item)
  return out
}

// A saved order (keys) after the shown keys, in that saved order, are
// rearranged into shownNew. The saved order can hold keys that aren't shown
// (windows on other workspaces, apps not running): those keep their places,
// and the shown keys trade places among the slots they already hold. Shown
// keys the order lacks are added at the end first.
function placeWithin(order, shown, shownNew) {
  var result = (order || []).slice()
  for (var i = 0; i < shown.length; i++) {
    if (result.indexOf(shown[i]) < 0) result.push(shown[i])
  }
  var slots = []
  for (var j = 0; j < result.length; j++) {
    if (shown.indexOf(result[j]) >= 0) slots.push(j)
  }
  for (var k = 0; k < slots.length; k++) result[slots[k]] = shownNew[k]
  return result
}

if (typeof module !== "undefined") {
  module.exports = { dropIndex: dropIndex, dragShift: dragShift, moved: moved, placeWithin: placeWithin }
}
