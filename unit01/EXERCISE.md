# Unit 1 practice: read a core network policy (offline)

Open `core-network-policy.json` in any text editor. No AWS account is needed, and nothing here
creates or changes anything in AWS. The policy is a teaching example; the ASN range and
Regions are illustrative.

Four attachments are requested. Each line shows the attachment type, its Region and the tags
on the **attachment**:

| # | Attachment | Region | Attachment tags |
|---|---|---|---|
| A | VPC "payments" | us-east-1 | segment = prod |
| B | VPC "build-agents" | eu-west-1 | segment = dev |
| C | VPC "directory" | us-east-1 | segment = shared |
| D | VPC "reporting" | eu-west-1 | segment = Prod |

## Questions
1. How many core network edges does this policy create, and in which Regions?
2. Which segment does each attachment A to D join? Which ones wait for someone to accept them?
3. Can A reach C? Can B reach C? Can A reach B? Why?
4. Attachment D was meant for prod. What happens to it, and what is the fix?
5. The team adds `"ap-southeast-2"` to edge-locations. What does Cloud WAN build, and do you need any
   peering or static routes for prod to work there?
6. Someone proposes changing `"share-with": ["prod", "dev"]` to `"share-with": "*"`.
   Would prod and dev then reach each other? (Hint: a share connects the segment with each listed
   segment, not the listed segments with each other.)

## Answers
1. Two: us-east-1 and eu-west-1. Each edge gets an ASN from 64512-64555, and the two edges peer automatically.
2. A → prod, B → dev, C → shared. D → no segment (see 4). A and C need acceptance (default `true`);
   B joins automatically because dev sets `require-attachment-acceptance` to false.
3. A ↔ C yes and B ↔ C yes, through the share action. A ↔ B no: prod and dev are separate routing domains,
   and the share does not connect the listed segments with each other.
4. The tag value `Prod` must exactly match a segment name, and `Prod` is not `prod`, so no
   rule maps it to a segment and it gets no routes. Fix the tag on the attachment to `prod`.
5. A third core network edge in ap-southeast-2, peered with the other edges, with the same segments. No peering
   or static routes are needed; attachments there still need the segment tag (and acceptance for prod).
6. No. With `*`, shared is shared with every segment, but each listed segment still has no routes to the others.

Sources: AWS Cloud WAN User Guide, "Core network policy version parameters" and "What is AWS Cloud WAN?"
(checked 13 Nov 2026).
