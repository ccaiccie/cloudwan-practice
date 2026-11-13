# Optional manual guide: evaluate the flows by hand

No scripts, no AWS. Print `core-network-policy.json` and `scenarios/onprem-routes.json`, or open them side by side.

## The procedure, for each route

1. **Direct Connect gateway first.** Cross out any community that is large (three numbers), extended (has letters, such as `rt:`), or starts with 7224, 10124, 17493, 9059 or 4001. Only standard `ASN:value` communities with your own ASN remain.
2. **Pick the policies for the scope.** Attachment scope: find the `attachment-routing-policy-rules` whose label matches the attachment and whose `edge-locations` include this edge (or have none). Keep the policies with the direction you are evaluating. Share or edge-pair scope: the `routing-policy-names` on that segment action.
3. **Order them.** Lowest `routing-policy-number` first; inside a policy, lowest `rule-number` first.
4. **Walk the rules.** A rule matches when all conditions match (`and`) or any matches (`or`). `prefix-in-cidr` matches only prefixes inside the CIDR, not the CIDR itself.
   - `drop` or `allow`: stop. That is the result.
   - Anything else (`add-community`, `prepend-asn-list`, `set-local-preference`, `set-med`, `remove-community`): change the route and continue.
5. **No terminal rule matched?** The route is allowed, with any changes.

## Worksheet

| Route | After DX | prod (prodOnlyIn) | dr (drOnlyIn) | eu-west-1 inbound | edge pair to eu-west-1 |
|---|---|---|---|---|---|
| 10.10.0.0/16 | | | | | |
| 10.11.0.0/16 | | | | | |
| 10.20.0.0/16 | | | | | |
| 10.30.0.0/16 | | | | | |
| 10.40.0.0/16 | | | | | |
| 10.50.0.0/16 | | | | | |

Check your worksheet against `tests/expected/02` to `06`.

## If you later try this in a real account

This course takes no AWS actions, and this lab doesn't need any. If you build it yourself in a lab account, routing policies require core network policy version 2025.11, Direct Connect gateway attachments and core network edges have charges, and the post-policy routes are shown by `get-network-routes` or the console route view. `list-core-network-routing-information` shows routes before policies are applied. Read the current AWS Cloud WAN routing policy and Direct Connect documentation first.
