# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# One raw line in, one JSON object out; $level, $tag, $stage are the stream’s, $ARGS.positional the image rules
def pair: "[A-Za-z_][A-Za-z0-9_.-]*=(?:\"(?:[^\"\\\\]|\\\\.)*\"|[^\\s\"]*)";

# Levels every native spelling lands on
def levels: {
  emerg: "error", emergency: "error", alert: "error", crit: "error", critical: "error", fatal: "error", panic: "error",
  severe: "error", err: "error", error: "error",
  warn: "warn", warning: "warn",
  notice: "info", info: "info", information: "info", informational: "info",
  debug: "debug", trace: "debug"
};

# A native level as one of four, an unknown one as the stream’s
def normal: levels[ascii_downcase? // ""] // $level;

# UTC now with milliseconds, as b19-log writes it
def stamp: now | "\(floor | strftime("%Y-%m-%dT%H:%M:%S")).\((. - floor) * 1000 | floor + 1000 | tostring | .[1:])Z";

# Fields of a line that is key=value pairs and nothing else, the first spelling of a key winning
def pairs:
  select(test("^\\s*\(pair)(?:\\s+\(pair))*\\s*$"))
  | reduce (match(pair; "g").string | capture("^(?<k>[^=]+)=(?<v>.*)$")) as $p ({};
      if has($p.k) then . else .[$p.k] = ($p.v | if startswith("\"") then .[1:-1] | gsub("\\\\(?<c>.)"; .c) else . end) end);

# Fields of the first image rule that matches; a rule that fails is skipped
def ruled: . as $line | first($ARGS.positional[] | . as $rule | try ($line | capture($rule)) catch empty);

# The record: parsed fields, the engine’s own keys over them, the native line kept whenever msg differs
def record($fields; $line):
  ($fields + {
    time: stamp,
    level: ($fields.level | normal),
    tag: $tag
  } + (if $stage == "" then {} else {stage: $stage} end)) as $record
  | if $record.msg == $line then $record | del(.raw) else $record + {raw: $line} end;

. as $line
| try (
    (if startswith("{") then try fromjson catch null else null end) as $json
    | if ($json | type) == "object" then
        if $json | has("time") and has("level") then $line
        else {time: stamp, level: $level} + $json | tojson end
      else
        ((first(ruled | {msg: $line} + .) // first(pairs)) // {msg: $line}) as $fields
        | record($fields | del(.raw, .stage); $line) | tojson
      end
  ) catch (record({msg: $line}; $line) | tojson)
