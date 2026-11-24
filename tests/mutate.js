#!/usr/bin/env node
// Mutation check: plants each entry of tests/mutations.json, one at a time,
// on a scratch copy of the repo, and expects the test suite to fail.
// A mutant the suite survives is behaviour no test really covers.
//
//   node tests/mutate.js            node and script tests (about a second each)
//   node tests/mutate.js --all      also the widget test (tests/widget.test.sh, ~20 s each)
//   node tests/mutate.js <name>...  only these mutants
//
// It copies only files git knows about (`git add` new test files first),
// runs the unmutated suite first and stops if that fails (a red baseline
// would count every mutant as killed), and names the checks that killed each
// mutant. The working copy is never touched.
"use strict"
const fs = require("fs")
const os = require("os")
const path = require("path")
const { execFileSync, spawnSync } = require("child_process")

const repo = path.resolve(__dirname, "..")
const args = process.argv.slice(2)
const all = args.includes("--all")
const only = args.filter((arg) => !arg.startsWith("--"))
const mutants = JSON.parse(fs.readFileSync(path.join(__dirname, "mutations.json"), "utf8"))
  .filter((mutant) => only.length === 0 || only.includes(mutant.name))

function copyRepo() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "transom-mutant-"))
  const files = execFileSync("git", ["ls-files", "-z"], { cwd: repo, encoding: "utf8" }).split("\0").filter(Boolean)
  for (const file of files) {
    const from = path.join(repo, file)
    if (!fs.existsSync(from)) continue
    fs.mkdirSync(path.join(dir, path.dirname(file)), { recursive: true })
    fs.copyFileSync(from, path.join(dir, file))
    fs.chmodSync(path.join(dir, file), fs.statSync(from).mode)
  }
  return dir
}

// Runs the suite in dir: { passed, failures: [names of failed checks] }.
function runSuite(dir) {
  const commands = [["node", ["tests/run.js"]], ["bash", ["tests/scripts.test.sh"]]]
  if (all) commands.push(["bash", ["tests/widget.test.sh"]])
  const failures = []
  for (const [command, commandArgs] of commands) {
    const run = spawnSync(command, commandArgs, { cwd: dir, encoding: "utf8", timeout: 180000 })
    const out = (run.stdout || "") + (run.stderr || "")
    for (const line of out.split("\n")) {
      const match = line.match(/^(?:FAIL|not ok -) (.*)/)
      if (match) failures.push(match[1].trim())
    }
    if (run.status !== 0 && failures.length === 0) failures.push(commandArgs.join(" ") + " exited " + run.status + (run.error ? " (" + run.error.message + ")" : ""))
  }
  return { passed: failures.length === 0, failures }
}

const baselineDir = copyRepo()
const baseline = runSuite(baselineDir)
fs.rmSync(baselineDir, { recursive: true, force: true })
if (!baseline.passed) {
  console.log("The unmutated suite fails, so no mutant can be judged:\n  " + baseline.failures.join("\n  "))
  process.exit(2)
}

let survivors = 0
for (const mutant of mutants) {
  const dir = copyRepo()
  try {
    const file = path.join(dir, mutant.file)
    const text = fs.readFileSync(file, "utf8")
    const count = text.split(mutant.find).length - 1
    if (count !== 1) {
      console.log("STALE   " + mutant.name + ": the text to change occurs " + count + " times in " + mutant.file)
      survivors++
      continue
    }
    fs.writeFileSync(file, text.replace(mutant.find, mutant.replace))
    const result = runSuite(dir)
    if (result.passed) {
      survivors++
      console.log("SURVIVED " + mutant.name + " (" + mutant.why + ")")
    } else {
      console.log("killed   " + mutant.name + "  <- " + result.failures[0] + (result.failures.length > 1 ? " (+" + (result.failures.length - 1) + ")" : ""))
    }
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
}
console.log("\n" + (mutants.length - survivors) + " of " + mutants.length + " killed")
process.exit(survivors ? 1 : 0)
