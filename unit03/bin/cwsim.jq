# cwsim.jq - offline simulation of AWS Cloud WAN routing-policy evaluation (teaching aid, not an AWS tool).
# Called by cwsim.sh. Inputs: $P (core network policy), $R (routes), $args (options).
def ip2n: split(".") | map(tonumber) | .[0]*16777216 + .[1]*65536 + .[2]*256 + .[3];
def pfx: split("/") | {n: (.[0] | ip2n), l: (.[1] | tonumber)};
def blk($l): if $l == 0 then 0 else (. / pow(2; 32 - $l) | floor) end;
def in_cidr($c): (pfx) as $r | ($c | pfx) as $k | ($r.l > $k.l) and (($r.n | blk($k.l)) == ($k.n | blk($k.l)));
def asnranges: [($P["core-network-configuration"]["asn-ranges"] // [])[] | split("-") | map(tonumber)];
def in_core($a): any(asnranges[]; $a >= .[0] and $a <= .[1]);
def ckind: if test("^[0-9]+:[0-9]+$") then (split(":") | map(tonumber)) as $v | (if $v[0] <= 65535 and $v[1] <= 65535 then "standard" else "invalid" end)
  elif test("^[0-9]+:[0-9]+:[0-9]+$") then "large" else "extended" end;
def reserved: [7224, 10124, 17493, 9059, 4001];
def vals: if type == "array" then .[] else tostring | split(",")[] | gsub("^ +| +$"; "") end;
def show($x): if $x == null then "-" else ($x | tostring) end;

# ---------- route normalisation and the Direct Connect gateway stage ----------
def norm: {prefix, path: (.["as-path"] // []), med: (.med // null), lp: (.["local-pref"] // null), comm: (.communities // [])};
def dx_now: . as $r | reduce ($r.comm[]) as $c ({r: ($r | .comm = []), log: []};
    ($c | ckind) as $k |
    if $k == "large" then .log += ["dx  \($r.prefix) removed \($c) (large community)"]
    elif $k == "extended" then .log += ["dx  \($r.prefix) removed \($c) (extended community)"]
    elif $k == "invalid" then .log += ["dx  \($r.prefix) removed \($c) (not a valid community)"]
    elif (reserved | index($c | split(":")[0] | tonumber)) != null then .log += ["dx  \($r.prefix) removed \($c) (AWS-reserved ASN)"]
    else .r.comm += [$c] end);
def dx_before: . as $r | {r: ($r | .comm = []), log: [$r.comm[] | "dx  \($r.prefix) removed \(.) (before Nov 2026: not carried to Cloud WAN)"]};

# ---------- policy selection ----------
def pols: $P["routing-policies"] // [];
def bynames($names): [pols[] | select(.["routing-policy-name"] as $n | $names | index($n))];
def bylabel($label; $edge; $dir): [($P["attachment-routing-policy-rules"] // []) | sort_by(.["rule-number"])[]
    | select(any(.conditions[]; .type == "routing-policy-label" and .value == $label))
    | select((.["edge-locations"] // null) == null or (.["edge-locations"] | index($edge)))
    | .action["associate-routing-policies"][]] | unique as $n
    | [pols[] | select((.["routing-policy-name"] as $x | $n | index($x)) and .["routing-policy-direction"] == $dir)];

# ---------- rule evaluation ----------
def cond($r): .value as $v | if .type == "prefix-equals" then $r.prefix == $v
  elif .type == "prefix-in-cidr" then ($r.prefix | in_cidr($v))
  elif .type == "asn-in-as-path" then ($r.path | index($v | tonumber)) != null
  elif .type == "community-in-list" then any($v | vals; . as $c | $r.comm | index($c) != null)
  elif .type == "med-equals" then $r.med == ($v | tonumber)
  else error("match condition \(.type) is not simulated") end;
def matches($r): .["rule-definition"] as $d | [$d["match-conditions"][] | cond($r)] as $m
  | if ($d["condition-logic"] // "and") == "or" then any($m[]; .) else all($m[]; .) end;
def act($a): if $a.type == "set-local-preference" then .lp = ($a.value | tonumber)
  elif $a.type == "set-med" then .med = ($a.value | tonumber)
  elif $a.type == "prepend-asn-list" then .path = ([$a.value | if type == "array" then .[] else vals | tonumber end] + .path)
  elif $a.type == "remove-asn-list" then ([$a.value | if type == "array" then .[] else vals | tonumber end]) as $x | .path = [.path[] | select(. as $p | $x | index($p) | not)]
  elif $a.type == "add-community" then reduce ($a.value | vals) as $c (.; if (.comm | index($c)) then . else .comm += [$c] end)
  elif $a.type == "remove-community" then ([$a.value | vals]) as $x | .comm = [.comm[] | select(. as $c | $x | index($c) | not)]
  else error("action \($a.type) is not simulated") end;
def evaluate($ps): . as $r0 | reduce ($ps[] as $p | $p["routing-policy-rules"] | sort_by(.["rule-number"])[] | {p: $p["routing-policy-name"], rule: .}) as $x
    ({r: $r0, verdict: null, by: "default"};
     .r as $cur | if .verdict != null then . elif ($x.rule | matches($cur)) | not then .
     else ($x.rule["rule-definition"].action) as $a | "\($x.p)#\($x.rule["rule-number"])" as $id
       | if $a.type == "drop" then .verdict = "DROP" | .by = $id
         elif $a.type == "allow" then .verdict = "ALLOW" | .by = $id
         else .r |= act($a) | .mods += [$id] end end)
  | .verdict //= "ALLOW";
def line: if .verdict == "DROP" then "DROP  \(.r.prefix) by=\(.by)"
  else "ALLOW \(.r.prefix) by=\(.by)\(if .mods then " changed-by=" + (.mods | join(",")) else "" end) as-path=\(if (.r.path | length) == 0 then "-" else (.r.path | map(tostring) | join(" ")) end) med=\(show(.r.med)) lp=\(show(.r.lp)) communities=\(if (.r.comm | length) == 0 then "-" else (.r.comm | join(",")) end)" end;

# ---------- lint ----------
def lint: [
  (if ($P["routing-policies"] // [] | length) > 0 and $P.version != "2025.11" then "ERROR version is \($P.version // "missing"); routing policies need 2025.11" else empty end),
  (pols[] | . as $p | .["routing-policy-name"] as $n |
    (if ($n | test("^[A-Za-z0-9]{1,100}$")) then empty else "ERROR policy name \($n): letters and digits only, max 100" end),
    (if (.["routing-policy-direction"] | IN("inbound", "outbound")) then empty else "ERROR \($n): direction must be inbound or outbound" end),
    (if (.["routing-policy-number"] | . >= 1 and . <= 9999) then empty else "ERROR \($n): routing-policy-number must be 1-9999" end),
    ([.["routing-policy-rules"][]["rule-number"]] | if length != (unique | length) then "ERROR \($n): duplicate rule-number" else empty end),
    (.["routing-policy-rules"] | sort_by(.["rule-number"])) as $rs |
    ($rs | to_entries[] | .value as $r | .key as $i | $r["rule-definition"] as $d |
      ($d["match-conditions"][] | select(.type == "community-in-list")), ($d.action | select(.type | IN("add-community", "remove-community"))) | .value | vals | . as $c |
        (if ($c | ckind) != "standard" then "ERROR \($n)#\($r["rule-number"]): \($c) is not a standard community (ASN:value)"
         elif in_core($c | split(":")[0] | tonumber) then "ERROR \($n)#\($r["rule-number"]): \($c) uses an ASN inside the core network asn-ranges"
         elif (reserved | index($c | split(":")[0] | tonumber)) then "WARN  \($n)#\($r["rule-number"]): \($c) starts with an AWS-reserved ASN; avoid it (Direct Connect removes these from routes it receives)"
         else empty end)),
    ($rs | to_entries[] | select(.value["rule-definition"].action.type | IN("drop", "allow")) | select(any(.value["rule-definition"]["match-conditions"][]; .type == "prefix-in-cidr" and .value == "0.0.0.0/0")) | .key as $k
      | select($k < ($rs | length) - 1) | "WARN  \($n)#\(.value["rule-number"]): terminal catch-all before later rules; rules after it never run for matched routes"),
    ($rs[] | select(.["rule-definition"].action.type == "summarize" and $p["routing-policy-direction"] != "outbound") | "ERROR \($n)#\(.["rule-number"]): summarize is outbound only")),
  (([pols[]["routing-policy-name"]]) as $names | [$P["core-network-configuration"]["edge-locations"][]?.location] as $edges |
    (($P["attachment-routing-policy-rules"] // [])[] | (.action["associate-routing-policies"][] | select(. as $x | $names | index($x) | not) | "ERROR attachment rule references unknown routing policy \(.)"),
       ((.["edge-locations"] // [])[] | select(. as $e | $edges | index($e) | not) | "ERROR attachment rule edge-location \(.) is not in core-network-configuration")),
    (($P["segment-actions"] // [])[] | ((.["routing-policy-names"] // [])[], (.["edge-location-association"]["routing-policy-names"] // [])[]) | select(. as $x | $names | index($x) | not) | "ERROR segment action references unknown routing policy \(.)"))
];

# ---------- main ----------
if $args.lint then (lint | if length == 0 then "LINT OK" else .[] end)
else
  (if $args.names then bynames($args.names | split(",")) else bylabel($args.label; $args.edge; $args.direction) end | sort_by(.["routing-policy-number"])) as $ps
  | "policies: \(if ($ps | length) == 0 then "(none)" else ($ps | map("\(.["routing-policy-name"])(#\(.["routing-policy-number"]) \(.["routing-policy-direction"]))") | join(" ")) end)",
    ($R.routes[] | norm | (if $args.dx == "now" then dx_now elif $args.dx == "before" then dx_before else {r: ., log: []} end) as $s
      | ($s.log[]), ($s.r | evaluate($ps) | line))
end
