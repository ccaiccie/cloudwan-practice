# Unit 3 exercise: communities over Direct Connect, simulated

Work in this folder. Use either `bin/cwsim.sh` (Bash) or `bin/cwsim.ps1` (PowerShell 7). Commands below are Bash; the PowerShell parameters are listed in README.md. Answers are at the end.

The community plan used by the on-premises team (illustrative):

| Community | Meaning |
|---|---|
| 65001:100 | production route |
| 65001:200 | disaster recovery route |
| 65001:310 | enter AWS through us-east-1 for this prefix |
| 65001:400 | this prefix must stay in us-east-1 |
| 65001:1001 / 65001:1002 | added by Cloud WAN: advertised by the us-east-1 / eu-west-1 edge |

## Task 1: before and after
Run case 01 and case 02:
```bash
bin/cwsim.sh --policy core-network-policy.json --routes scenarios/onprem-routes.json --names prodOnlyIn --via-dx-before
bin/cwsim.sh --policy core-network-policy.json --routes scenarios/onprem-routes.json --names prodOnlyIn --via-dx
```
1. Before the change, how many on-premises routes reach the prod segment, and why?
2. After the change, which routes reach prod?

## Task 2: the route that was tagged the wrong way
3. 10.50.0.0/16 carries three communities on-premises. Why does it still not reach prod? What should the on-premises team change?

## Task 3: prod versus DR
4. Run the same with `--names drOnlyIn`. Which routes reach the dr segment? Does any route reach both prod and dr?

## Task 4: per-Region treatment
Run the inbound policies the eu-west-1 edge applies to the Direct Connect attachment:
```bash
bin/cwsim.sh --policy core-network-policy.json --routes scenarios/onprem-routes.json --label dxOnPrem --edge eu-west-1 --direction inbound --via-dx
```
5. What happens to 10.30.0.0/16 and why? Why does the policy also associate `keepInUsEast1` on the eu-west-1 to us-east-1 edge pair?
6. What happens to 10.11.0.0/16, and what is the intended effect?
7. Run the same for `--edge us-east-1`. Why does it say `policies: (none)`?

## Task 5: communities back on-premises
8. Run cases 07 and 08 (see `tests/cases.txt`). What do on-premises routers learn from 65001:1001 and 65001:1002, and what can they do with it? What happened to the branch route's existing community 65010:50?

## Task 6: lint
9. Run `bin/cwsim.sh --policy scenarios/broken-policy.json --lint`. Explain each finding in one line.

## Task 7: change one line
10. In a copy of the policy, change `prodOnlyIn` rule 100 to match `65001:200`. Predict the result for prod before you run it, then run it.

---

## Answers

1. None. The old behaviour removed communities between the virtual interface and the core network, so every route arrives untagged and rule 200 drops it. This is why people used a Site-to-Site VPN overlay (communities were honoured on VPN and Connect attachments) or copied prefix lists into the AWS policy by hand.
2. 10.10.0.0/16, 10.11.0.0/16 and 10.30.0.0/16: the routes tagged 65001:100. 10.20 (DR) and 10.40 (untagged) are dropped by rule 200.
3. All three of its communities are removed by the Direct Connect gateway: 65001:100:7 is a large community, rt:65001:100 is an extended community, and 7224:7300 starts with an AWS-reserved ASN. Only standard communities with your own ASN in the first position are carried. Tag it with standard 65001:100. (7224:7300 is a Direct Connect local preference tag; it is not carried into Cloud WAN.)
4. Only 10.20.0.0/16. No route reaches both, because each share admits only its own tag. One Direct Connect attachment in one hybrid segment now serves both prod and dr.
5. It is dropped (`keepInUsEast1#100`) because it carries 65001:400. A Direct Connect gateway attachment is associated with several edges, so the eu-west-1 edge would learn it directly; that drop is scoped to eu-west-1 with `edge-locations`. The edge-pair association blocks the second path: the same route arriving at eu-west-1 from the us-east-1 edge across the core network mesh.
6. Its AS path becomes `65001 65001 65001` at eu-west-1 only (`enterViaUsEast1#100`). Cloud WAN compares AS path length first, so a shorter path for the same prefix, such as the one learned at us-east-1, is preferred. The on-premises team chooses the entry Region per prefix by tagging; no AWS policy change.
7. The us-east-1 rule associates only `markUsEast1`, which is an outbound policy. Inbound, nothing applies there, so all routes are allowed unchanged (default allow).
8. Which Region advertised each route. On-premises policy can set local preference by that community, for example prefer us-east-1 for 10.100.0.0/16. The branch's 65010:50 is kept and passed on: communities are transitive and `add-community` adds rather than replaces.
9. Version must be 2025.11 for routing policies. Names allow letters and digits only. 65001:200:1 is a large community, not a standard one. Rule 50 allows everything, so the drop below it never runs. 64520 is inside the core network ASN range, which communities must not use. 7224 is AWS-reserved. The share references `prodOnlyIn`, which no longer exists after the rename.
10. Prod receives only 10.20.0.0/16, the DR route; everything else is dropped by rule 200. One changed value moves production traffic: review the change set before running a policy version.
