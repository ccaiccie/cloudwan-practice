# Unit 3 practice lab: BGP communities on Direct Connect attachments (offline)

This lab runs on your computer only. It reads JSON files and prints results. It never calls AWS, needs no AWS account and costs nothing.

`cwsim` is a small **teaching simulator** of how a Cloud WAN core network evaluates routing policies against routes that carry BGP communities. It follows the rules in the AWS documentation (rule order, terminal `allow` and `drop`, default allow, `prefix-in-cidr` not matching the prefix itself, Direct Connect community restrictions). It is not an AWS tool and it does not model everything: best-path selection, prefix lists, summarization and AS-path replacement are not simulated.

## Files

| Path | What it is |
|---|---|
| `core-network-policy.json` | The policy from Unit 3 (version 2025.11): segments hybrid, prod, dr; the share and edge-pair actions; routing policies; attachment routing policy rules for the Direct Connect attachment label `dxOnPrem`. |
| `scenarios/onprem-routes.json` | What the on-premises router advertises over the transit virtual interface, with communities. |
| `scenarios/aws-routes-*.json` | What each core network edge advertises back toward the Direct Connect gateway. |
| `scenarios/broken-policy.json` | A policy with six mistakes for the lint exercise. |
| `bin/cwsim.sh` + `bin/cwsim.jq` | Bash version. Needs `bash` and `jq` 1.6 or later. |
| `bin/cwsim.ps1` | PowerShell 7 version. No other tools needed. Same output, line for line. |
| `tests/` | `cases.txt`, expected outputs, `run-tests.sh` and `run-tests.ps1`. |
| `EXERCISE.md` | The tasks and questions, with answers at the end. |
| `MANUAL-GUIDE.md` | Optional: the same flows evaluated by hand, no scripts. |

## Set up

- **Windows, PowerShell 7:** nothing to install. If scripts are blocked, run `Unblock-File -Path .\bin\*.ps1, .\tests\*.ps1` once in this folder.
- **Bash (Linux, macOS, WSL or Git Bash):** install jq, for example `sudo apt install jq`, `brew install jq` or `winget install jqlang.jq`.

## Run the tests first

```bash
bash tests/run-tests.sh          # Bash
```
```powershell
pwsh -File tests/run-tests.ps1   # PowerShell 7
```
Both should end with `12 passed, 0 failed`.

## Run one evaluation

Evaluate named policies against a route file, with the Direct Connect gateway community rules applied first:

```bash
bin/cwsim.sh --policy core-network-policy.json --routes scenarios/onprem-routes.json --names prodOnlyIn --via-dx
```
```powershell
./bin/cwsim.ps1 -Policy core-network-policy.json -Routes scenarios/onprem-routes.json -Names prodOnlyIn -ViaDx
```

Or let the simulator pick the policies the way the core network would, from the attachment's routing policy label, the edge and the direction:

```bash
bin/cwsim.sh --policy core-network-policy.json --routes scenarios/onprem-routes.json --label dxOnPrem --edge eu-west-1 --direction inbound --via-dx
```
```powershell
./bin/cwsim.ps1 -Policy core-network-policy.json -Routes scenarios/onprem-routes.json -Label dxOnPrem -Edge eu-west-1 -Direction inbound -ViaDx
```

Check a policy for common mistakes: `bin/cwsim.sh --policy FILE --lint` or `./bin/cwsim.ps1 -Policy FILE -Lint`.

`--via-dx-before` (`-ViaDxBefore`) shows the old behaviour, when no communities reached Cloud WAN over Direct Connect.

## Reading the output

```
dx  10.50.0.0/16 removed 65001:100:7 (large community)
ALLOW 10.10.0.0/16 by=prodOnlyIn#100 as-path=65001 med=- lp=- communities=65001:100
DROP  10.20.0.0/16 by=prodOnlyIn#200
```
- `dx` lines: what the Direct Connect gateway removed before the route reached the core network.
- `by=` the rule that decided (`policy#rule`), or `default` when no terminal rule matched (default allow).
- `changed-by=` non-terminal rules that modified the route on the way.

All prefixes, ASNs and community values are illustrative.
