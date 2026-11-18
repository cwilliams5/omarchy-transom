// Reads a widget's settings from its layout entry (transom.json) against the widget's
// spec. Each widget model (TasksModel.js, TrayModel.js) exports a spec:
//
//   { name: { default: …, choices: [...]?, min: n?, max: n? } }
//
// The default's type says what's accepted. A string with choices takes one
// of them; a boolean takes true or false; a number takes any number, rounded
// and clamped to min..max; a list ([]) takes a list of non-empty strings.
// Anything else is ignored and reported, so a typo never breaks the bar.

// A list from QML as a plain array. A list that came through a QML property
// (a layout entry handed to a widget) can arrive as a Qt sequence,
// which Array.isArray rejects but which still has length and indexes.
function toList(value) {
  if (!value || typeof value === "string") return null
  if (Array.isArray(value)) return value
  if (typeof value.length !== "number") return null
  var out = []
  for (var i = 0; i < value.length; i++) out.push(value[i])
  return out
}

// Returns { settings, problems }: every setting (default unless the entry
// has a valid value), and a sentence for each value that was ignored.
function parse(entry, spec) {
  var source = entry && typeof entry === "object" ? entry : {}
  var settings = {}
  var problems = []
  for (var key in spec) {
    var rule = spec[key]
    var fallback = rule.default
    settings[key] = Array.isArray(fallback) ? fallback.slice() : fallback
    if (!(key in source) || source[key] === undefined) continue
    var value = source[key]
    var shown = JSON.stringify(value)
    if (rule.choices) {
      if (rule.choices.indexOf(value) >= 0) settings[key] = value
      else problems.push(key + " must be one of " + rule.choices.join(", ") + " (got " + shown + ")")
    } else if (typeof fallback === "boolean") {
      if (typeof value === "boolean") settings[key] = value
      else problems.push(key + " must be true or false (got " + shown + ")")
    } else if (typeof fallback === "number") {
      if (typeof value === "number" && isFinite(value)) {
        var min = rule.min !== undefined ? rule.min : -Infinity
        var max = rule.max !== undefined ? rule.max : Infinity
        settings[key] = Math.round(Math.max(min, Math.min(max, value)))
      } else {
        problems.push(key + " must be a number (got " + shown + ")")
      }
    } else if (Array.isArray(fallback)) {
      var list = toList(value)
      if (list === null) {
        problems.push(key + " must be a list like [\"name\"] (got " + shown + ")")
      } else {
        settings[key] = list.filter(function(item) { return typeof item === "string" && item.trim() !== "" })
          .map(function(item) { return item.trim() })
        if (settings[key].length !== list.length) problems.push(key + " skipped entries that aren't names")
      }
    }
  }
  // id and enabled belong to the bar, not the widget: every entry may have them.
  for (var extra in source) {
    if (extra !== "id" && extra !== "enabled" && !(extra in spec)) problems.push("unknown setting " + extra)
  }
  return { settings: settings, problems: problems }
}

// Every setting's default, as a plain object.
function defaults(spec) {
  var out = {}
  for (var key in spec) out[key] = Array.isArray(spec[key].default) ? spec[key].default.slice() : spec[key].default
  return out
}

if (typeof module !== "undefined") {
  module.exports = { toList: toList, parse: parse, defaults: defaults }
}
