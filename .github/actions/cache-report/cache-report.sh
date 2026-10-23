#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Reports how well the BuildKit cache worked in a bake build: cached vs executed
# build steps per target, the slowest steps, cache import results and cache
# export durations. docker/bake-action's own summary only shows an overall
# cache figure, so this reads the build records of the builder instead.
#
#   cache-report.sh run <builder> <dir>        collect + render, never fails
#   cache-report.sh collect <builder> <dir>    write <dir>/records.jsonl and <dir>/logs/<n>.log
#   cache-report.sh render <dir>               write <dir>/cache-report.json and append the
#                                              markdown to $GITHUB_STEP_SUMMARY (or stdout)
#
# Environment (render): TITLE  optional suffix of the summary heading, e.g. "amd64"
#
# `render` is covered by tests/cache-report.test.sh.
#
# The logs come from `docker buildx history logs` (plain progress), which works
# after the bake step because buildx keeps a record of every build. Lines parsed:
#   #5 [2/3] RUN ...                         step name, first line of an id
#   #5 CACHED | #5 DONE 12.3s | #5 ERROR...  step result
#   #7 [core] importing cache manifest from <ref>   cache import (DONE = found, ERROR = not found)
#   #9 [core] exporting cache to registry     cache export (duration = its DONE time)
set -euo pipefail

MAX_BUILDS=20
MAX_TARGETS=30
MAX_IMPORTS=30
MAX_EXPORTS=10
MAX_SLOWEST=15
MAX_NAME=90

# Prints "<rec>\t<id>\t<status>\t<seconds>\t<name>" for each step of a plain log on stdin.
parse_log() {
  awk -v rec="$1" '
    /^#[0-9]+ / {
      id = substr($1, 2)
      rest = substr($0, length($1) + 2)
      if (!(id in seen)) { seen[id] = 1; order[++n] = id; name[id] = rest }
      if (rest == "CACHED") status[id] = "CACHED"
      else if (rest ~ /^DONE( [0-9.]+s)?$/) {
        if (status[id] != "ERROR") status[id] = "DONE"
        if (rest ~ / /) dur[id] = substr(rest, 6, length(rest) - 6)
      } else if (rest ~ /^ERROR/) status[id] = "ERROR"
    }
    END {
      for (i = 1; i <= n; i++) {
        id = order[i]
        gsub(/\t/, " ", name[id])
        print rec "\t" id "\t" status[id] "\t" dur[id] "\t" name[id]
      }
    }'
}

collect() {
  local builder="$1" dir="$2" n=0 ref
  [[ "$builder" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "invalid builder name" >&2; return 1; }
  mkdir -p "$dir/logs"
  docker buildx history ls --builder "$builder" --format json >"$dir/records.jsonl"
  while read -r ref; do
    n=$((n + 1))
    # `ls` prints <node>/<builder>/<id>; `logs` only accepts the id and writes the log to stderr.
    docker buildx history logs --builder "$builder" --progress plain "${ref##*/}" >"$dir/logs/$n.log" 2>&1 \
      || echo "::warning::cache-report: no log for build record $ref"
  done < <(jq -r '.ref' "$dir/records.jsonl")
}

render() {
  local dir="$1" n=0 name out="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
  : >"$dir/steps.tsv"
  while read -r name; do
    n=$((n + 1))
    [[ -f "$dir/logs/$n.log" ]] && parse_log "$name" <"$dir/logs/$n.log" >>"$dir/steps.tsv"
  done < <(jq -r '.name' "$dir/records.jsonl")

  jq -n -R --slurpfile rec "$dir/records.jsonl" '
    def prefix: "^\\[(?!internal\\])([A-Za-z0-9._-]+)\\] ";
    def secs: sub("\\.[0-9]+"; "") | fromdate;
    [inputs | split("\t") | {
        rec: .[0], status: .[2], name: .[4],
        dur: (if .[3] == "" then null else (.[3] | tonumber) end)}
      | .target = (((.name | match(prefix) | .captures[0].string) // null) // .rec)
      | .name = (.name | sub(prefix; ""))
      | .kind = (if (.name | test("^importing cache manifest from ")) then "import"
                 elif (.name | test("^exporting cache to ")) then "export"
                 elif (.name | test("^\\[[^\\]]*[0-9]+/[0-9]+\\]")) then "build"
                 else "other" end)] as $steps
    | {
        builds: [$rec[] | {name, ref, status, cached_steps, total_steps,
                           duration_s: ((.completed_at | secs) - (.created_at | secs))}],
        targets: ($steps | map(select(.kind == "build")) | group_by(.target) | map({
            target: .[0].target,
            cached: (map(select(.status == "CACHED")) | length),
            executed: (map(select(.status == "DONE")) | length),
            failed: (map(select(.status == "ERROR")) | length),
            executed_s: ([.[] | select(.status == "DONE") | .dur // 0] | add // 0)})),
        slowest: ($steps | map(select(.kind == "build" and .status == "DONE" and .dur != null))
                  | sort_by(-.dur) | .[:50] | map({target, name: .name[:200], seconds: .dur})),
        imports: ($steps | map(select(.kind == "import")) | map({
            target, tag: (.name | sub("^importing cache manifest from "; "") | sub("^.*:"; "")),
            found: (.status == "DONE"), seconds: .dur})),
        exports: ($steps | map(select(.kind == "export")) | map({target, status, seconds: .dur}))
      }' "$dir/steps.tsv" >"$dir/cache-report.json"

  jq -r --arg title "${TITLE:-}" --argjson nb "$MAX_BUILDS" --argjson nt "$MAX_TARGETS" \
    --argjson ni "$MAX_IMPORTS" --argjson ne "$MAX_EXPORTS" --argjson ns "$MAX_SLOWEST" \
    --argjson nm "$MAX_NAME" '
    def fmt: if . == null then "-" elif . >= 60 then "\(. / 60 | floor)m \(. % 60 | floor)s" else "\(.)s" end;
    def esc: (if length > $nm then .[:$nm - 3] + "..." else . end)
             | gsub("\\|"; "\\|") | gsub("`"; "\u0027") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
    def table($head; $rows; $cap):
      if ($rows | length) == 0 then "_none_\n"
      else $head + "\n" + ($head | gsub("[^|]"; "-") | gsub("-+"; "---")) + "\n"
           + ($rows[:$cap] | map("| " + join(" | ") + " |") | join("\n")) + "\n"
           + (if ($rows | length) > $cap
              then "\n_... and \(($rows | length) - $cap) more (see cache-report.json)_\n" else "" end)
      end;
    "### Build cache report\(if $title == "" then "" else " (\($title))" end)\n",
    "#### Builds\n",
    table("| Build | Status | Duration | Cached / total steps |";
          [.builds[] | [(.name | esc), .status, (.duration_s | fmt), "\(.cached_steps) / \(.total_steps)"]]; $nb),
    "\n#### Build steps per target\n",
    table("| Target | Cached | Executed | Failed | Time in executed steps |";
          [.targets[] | [(.target | esc), .cached, .executed, .failed, (.executed_s | fmt)]]; $nt),
    "\n#### Cache import\n",
    table("| Target | Cache tag | Result | Time |";
          [.imports[] | [(.target | esc), "`\(.tag | esc)`",
                         (if .found then "found" else "not found" end), (.seconds | fmt)]]; $ni),
    "\n#### Cache export\n",
    table("| Target | Result | Duration |";
          [.exports[] | [(.target | esc),
                         (if .status == "DONE" then "done" else (.status // "unknown") end), (.seconds | fmt)]]; $ne),
    "\n#### Slowest steps\n",
    table("| Target | Step | Duration |";
          [.slowest[] | [(.target | esc), "`\(.name | esc)`", (.seconds | fmt)]]; $ns)
    ' "$dir/cache-report.json" >>"$out"
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    run)
      local builder="${2:?builder required}" dir="${3:?dir required}"
      { collect "$builder" "$dir" && render "$dir"; } \
        || echo "::warning::cache-report failed; the build result is not affected."
      ;;
    collect) collect "${2:?builder required}" "${3:?dir required}" ;;
    render) render "${2:?dir required}" ;;
    *) echo "usage: $0 run|collect|render ..." >&2; exit 2 ;;
  esac
}

main "$@"
