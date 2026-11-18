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

// ---------------------------------------- dragging a whole widget (BarWindow.qml)

// Where a widget dragged along the bar would land. sides is
// { left: [...], right: [...] }: each side section's widgets in order as
// { id, x, width } in bar coordinates, leaving out the dragged one. centerX
// is the dragged widget's center now, middle the bar's middle. The left half
// of the bar drops into the left section and the right half into the right
// one, before the first widget whose center is past it. Show desktop stays
// last, in the corner. Returns { section, index }.
function dropSpot(sides, centerX, middle) {
  var section = centerX < middle ? "left" : "right"
  var list = (sides && sides[section]) || []
  var index = 0
  for (var i = 0; i < list.length; i++) {
    if (list[i].x + list[i].width / 2 < centerX) index = i + 1
  }
  if (list.length > 0 && list[list.length - 1].id === "showdesktop") index = Math.min(index, list.length - 1)
  return { section: section, index: index }
}

// Where the widgets of one side section sit (their x) once a widget
// insertWidth wide goes in at insertAt (-1: nothing goes in). A left section
// grows rightward from edge, a right one leftward from edge. Returns
// { xs, gapX }: the given widgets' x in order, and the inserted one's x.
function sidePositions(widths, side, edge, insertAt, insertWidth) {
  var all = (widths || []).slice()
  var inserting = insertAt >= 0 && insertAt <= all.length
  if (inserting) all.splice(insertAt, 0, insertWidth)
  var total = 0
  for (var i = 0; i < all.length; i++) total += all[i]
  var x = side === "left" ? edge : edge - total
  var positions = []
  for (var j = 0; j < all.length; j++) {
    positions.push(x)
    x += all[j]
  }
  var gapX = inserting ? positions.splice(insertAt, 1)[0] : null
  return { xs: positions, gapX: gapX }
}

// A layout ({ left, center, right } lists of entries) with widget id moved
// into section, before the entry beforeId. With no beforeId (or one that isn't
// there) it goes at the end, but never after a trailing show desktop. Each
// entry keeps its settings. Returns null when nothing would change.
function moveEntry(layout, id, section, beforeId) {
  var next = JSON.parse(JSON.stringify(layout || {}))
  var sections = ["left", "center", "right"]
  var entry = null
  for (var s = 0; s < sections.length && !entry; s++) {
    var list = next[sections[s]] || []
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        entry = list.splice(i, 1)[0]
        break
      }
    }
  }
  if (!entry || id === beforeId || sections.indexOf(section) < 0) return null
  if (!next[section]) next[section] = []
  var target = next[section]
  var at = -1
  if (beforeId) {
    for (var j = 0; j < target.length; j++) if (target[j].id === beforeId) { at = j; break }
  }
  if (at < 0) {
    at = target.length
    if (at > 0 && target[at - 1].id === "showdesktop") at--
  }
  target.splice(at, 0, entry)
  return JSON.stringify(next) === JSON.stringify(layout) ? null : next
}

if (typeof module !== "undefined") {
  module.exports = {
    dropIndex: dropIndex, dragShift: dragShift, moved: moved, placeWithin: placeWithin,
    dropSpot: dropSpot, sidePositions: sidePositions, moveEntry: moveEntry
  }
}
