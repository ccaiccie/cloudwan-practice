# Unit 2 exercise: read a community policy (offline)

Read `edge-router-policy.txt` and `routes.txt`. The configuration is illustrative IOS-style syntax; the ideas apply on any platform. Answers are at the end.

1. What does the provider receive for 10.10.0.0/16: which communities and which AS path?
2. What does the provider receive for 10.20.0.0/16? Which way does this influence traffic: into our network, or out of it?
3. 10.90.0.0/24 already carries 65001:900. What does it carry after `TO-PROVIDER`, and what does `no-export` ask the provider to do?
4. Remove the word `additive` from sequence 30. What changes?
5. Which provider route gets local preference 200 on our router, and what does that do to our outbound traffic?
6. 203.0.113.0/24 doesn't match sequence 10 of `FROM-PROVIDER`. Is it dropped?
7. Someone deletes `neighbor 192.0.2.1 send-community`. What does the provider see on this platform?
8. Why do we send 65001:200 instead of setting a low local preference for the DR routes ourselves?

---

## Answers

1. 65001:100, and AS path `65001` (our ASN is added when the route leaves our AS).
2. 65001:200 and AS path `65001 65001 65001`. The prepend makes the path look longer to others, so it influences traffic coming into our network. The community lets the provider apply its own policy too, if it publishes one.
3. It carries `65001:900 no-export`. `additive` adds to the existing list. `no-export` is a well-known community: the provider may use the route inside its own AS but must not advertise it to its external peers.
4. Without `additive`, `set community` replaces the list: the route carries only `no-export`, and 65001:900 is lost.
5. 198.51.100.0/24, tagged 64999:8100. Local preference is shared inside our AS only, and the higher value wins, so all our routers prefer this path for traffic leaving toward that prefix.
6. No. Sequence 20 is a permit with no match, so everything else is accepted with default attributes. A route-map that ends without a matching sequence denies the route, which is why the empty permit is there.
7. On Cisco IOS, communities are not sent to a neighbor unless `send-community` is configured, so the provider sees the routes without our tags. Other platforms send them by default. Check yours.
8. Local preference is not sent to external peers. We can't set the provider's local preference; we can only ask, using a community the provider has agreed to honour.
