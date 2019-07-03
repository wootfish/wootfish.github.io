---
layout: post
title: Idea Sketch for a Mesh Networking Protocol
---


Here's an idea for a mesh networking protocol that might actually scale well. The core construct is simple enough that I have to wonder if someone else has already come up with it. I hope so -- it'd be especially nice if they've already taken care of implementing it, too -- but just in case I'm the first, here's a sketch of what I have in mind. If you can point me to prior art, please do so I can add a link to it!

This is not a full specification, just the sketch of an idea. It's light on details in some areas because I'm not an expert and I know my limits.


### Addresses

First off, do away with any concept of assigning globally unique identifiers to anyone. This just doesn't scale, so we'll figure out a way to get by without it.

But how do we establish connections if we can't identify who we're connecting to? Well, in any mesh network, you're going to have two sorts of connections: first, via direct point-to-point radio between nearby peers; second, via messages relayed over a chain of such point-to-point radio links. The goal of a mesh network's routing protocol is to infer enough about the topography of those point-to-point links for us to establish efficient relay circuits over them.

This is easier said than done. Each point-to-point radio link has finite bandwidth which we have to be careful to conserve. Ideally, the routing layer's bandwidth overhead should be $$\mathcal{O}(1)$$ with respect to network size. Any weaker bound than this places an absolute upper limit on the network's size, as routing overhead is guaranteed to eventually saturate the network.

How do we meet this standard?

Let's assume we already have a way of establishing point-to-point radio connections with nearby peers.

Assign[^1] randomly distributed fixed-length addresses to peers, with no intimations at uniqueness. Each peer may have several addresses. These are less about _identifying_ peers and more about peers _claiming responsibility for_ certain regions of a shared, co-owned address space (somewhat like node IDs in Kademlia).

[^1]: Technically "assign" is a loaded word here. The implication of assignment coming from a central authority is not intended. Ideally peers' addresses would come from some sort of trapdoor proof-of-work function (possibly after hashing its output, if outputs are not already uniformly distributed). Peer addresses should somehow be made to expire after a fixed window of time, in order to complicate address squatting.

Define distance between addresses via the `xor` metric, and endow peers with responsibility for the addresses closest to their own IDs by this metric. Every peer serves as an introduction point for any target address which is close to their own address. Observe that for a target address $$a_t$$ with $$d_1 = a_1 \oplus a_t$$ and $$d_2 = a_2 \oplus a_t$$, the inequality $$d_1 < d_2$$ holds if and only if $$a_1$$ has more leading bits in common with $$a_t$$ than $$a_2$$ does.


### Bloom Filters

Every peer should be keeping a running list of everyone they have a point-to-point connection with, and they should keep track of every address claimed by the peers on the other ends of those connections.

Each peer can then determine the set of all addresses they can reach in one hop. They can then expand this set to contain all the addresses and _address prefixes_ they can reach in one hop. (see footnote for example)[^2]

[^2]: For example, say a peer has two active point-to-point connections. The first connected peer claims addresses `0000`, `0010`, and `0011`. The second peer claims `1111` and `1000`. The set of reachable addresses is then `{0000, 0010, 0011, 1111, 1000}` and the expanded set is `{0000, 0010, 0011, 1111, 1000, 000, 001, 111, 100, 00, 11, 10, 0, 1}`

From there, peers can produce _Bloom filters_[^3] representing these expanded sets.

[^3]: Using constant, globally fixed (and carefully determined) Bloom filter parameters.

These Bloom filters can then be sent over point-to-point peer connections along with local address information.

Any peer, upon receiving one-hop Bloom filters from all their own one-hop point-to-point connections, can combine these filters with logical OR to produce the union of the sets each filter represents. This union is precisely the set of addresses and address prefixes that the local peer can reach in two hops.

These two-hop filters can then be sent to adjacent peers as well. Doing this allows everyone to compute three-hop filters. Sending these yields four-hop filters, and so forth.

Of course, this process can't continue indefinitely. Eventually these filters reach a saturation point and their false positive probability skyrockets. The point at which this happens is straightforward to model for any given tolerance. Regardless of how the saturation point is determined, this iterative process of computing progressively broader Bloom filters should continue until this point is reached.

Rather than broadcasting an update whenever any of these filters changes -- which would take significant bandwidth -- peers could just broadcast these updates at regular intervals. We can check the effectiveness of this heuristically: If most peers' interval durations are under, say, $$t$$ seconds, then even if peers' intervals are out of phase (as they inevitably would be), a peer's updated routing info would propagate at peers $$n$$ hops away after no more than $$n t$$ seconds. With each interval the number of peers to which this info update has propogated can be expected to grow exponentially.


### Routing

Now, say we have an arbitrary target address and we want to figure out which peers, out of everyone we know about in the mesh, have the closest addresses to our target address. Recall that this is equivalent to figuring out whose addresses share the longest prefixes with our target. To get started, we can simply consult our Bloom filters. Start with the full address, and query each local Bloom filter for it, starting with the one-hop filter and working outwards. If we get a hit, check for a false positive by querying for every smaller prefix as well -- if any are missing, we've hit a false positive (this does not eliminate false positives but does allow us to filter some out).

If no hits are found for the full address, repeat the process for the address's longest prefix; if no hits are found, repeat for the next-longest. Repeat until a hit is found, and note which filter it was found in.

If this process determines that a given prefix is reachable in $$n$$ hops, the next step is to take our neighbors' $$n-1$$-hop filters and query these for the same prefix. If none turn up a hit, then our local hit was a false positive and we need to restart the search of our local filters. If any of these $$n-1$$-hop filters do hit, however, then we've determined that these peers would be valid next hops in a length-minimized path to the peer whose address is closest to our target.

Once we've figured this out, we might contact the peer(s) whose filter hit and ask them to forward routing queries on our behalf. Then we can query their neighbors' $$n-2$$-hop filters to identify the next step(s) in the path to our target. Repeat this process and we'll eventually get where we're going. The precise forwarding/proxying mechanism here is intentionally left somewhat ambiguous -- I'm imagining it resembling the protocol for establishing Tor circuits, but the specifics could go any number of ways, and I'm trying to avoid getting bogged down in details in this post.

Note that the iterative routing process is going to need to be able to handle Bloom filter false positives gracefully. This will involve some degree of backtracking. It might even be a good idea to try to run parallel disjoint lookups -- sort of like how S/Kademlia does[^4] -- in order to try and work around this.

[^4]: The analogue to S/Kademlia is limited, since that algorithm's underlying protocol stack is obviously very different, but their core idea applies. Carrying out a lookup over multiple disjoint paths in parallel increases the chance of following at least one path which does not contain malicious nodes; the same logic (and possibly even the same mathematical analysis) applies in the case of non-malicious interference, e.g. misleading routing info due to false positives from a Bloom filter.


### Connecting

What we have so far is a way of looking up an arbitrary target address and identifying, within the neighborhood of the network that we know about, the peers who have claimed responsibility for the closest addresses to our target. Of course, these peers could be anyone. If we have a friend, and we know our friend is on the network, we can't use this routing construct to directly find our friend and open a connection. We're not there yet.

However, we are _almost_ there. The idea of peers serving as _introduction points_ was mentioned earlier. Say we have a shared secret with our friend. We could derive an address from this shared secret[^5], look up this address to find the closest peers to it in our neighborhood of the network, and then ask these peers to introduce us to anyone else who connects to them looking for the same address that we are. This is easy for them to do, since everyone who connects has already charted a course through the mesh to arrive at these peers, and all that any of these peers has to do is knit together these circuits, with themselves as the connecting point.

[^5]: e.g. by taking current Unix time as an integer, shifting it right by some number of bits to limit resolution, and using this as the key for a hash of the shared secret -- or by taking, say, two or three such hashes for consecutive timestamps and attempting introductions at _all_ the resulting addresses in parallel. This second method, while higher-overhead, would increase the chances of a successful rendezvous, and would be more fault-tolerant in edge cases (e.g. when the two friends start their lookups at different times, or when their clocks are out of sync, etc etc).

If the address lookup bears a passing resemblance to Tor circuit negotiation, then this process could (if properly designed) end up resembling the process of connecting to an onion service. This is (obviously) not a guarantee of privacy or security by itself, but it _does_ seem to suggest that we could be headed in a promising direction.

This construct can support both anonymous and authenticated introductions.

The anonymous case vaguely resembles e.g. Mainline DHT, where peers wishing to join a torrent swarm look up the torrent's associated info hash as a DHT address, request a list of peers who have stored their contact info at that address, then add their own contact info to the list. We could mimic this idea 

The authenticated case could work any number of ways. It might look like this: suppose you and your friend each have an encrypted messenger app, and the app has (say) an Ed448 public key associated with your identity. Say you exchange public keys (e.g. by scanning QR codes on each other's phones). You can now use ECDH to obtain a shared secret. Now, whenever you want to attempt a connection over the network, derive an ephemeral _rendezvous address_ from your shared secret (or several such addresses)[^5], then look up these addresses, establish circuits over the network to the peers identified by this lookup process, and ask these peers to introduce us to anyone else who shows up asking about the same addresses.

Since the rendezvous address is known only to you, your friend, and any peers you've shared it with during the lookup process (e.g. the peer serving as our introduction point, at minimum), it is likely that the first and only connection you will see will be from your friend. Once this connection is established, you can mutually authenticate using your public keys and establish an encrypted channel (e.g. via Noise), and then you're good to go.


### Rerouting

So far, we have a way of making end-to-end connections between arbitrary peers as long as they know what address to look up to find each other. However, the routes they take to find each other might be wildly inefficient.

For instance, suppose you and your friend are two hops away from each other, but you're both five hops away from your rendezvous point. Then you'll end up establishing a ten-hop circuit when you could have a two-hop one. Not only will this impact the quality of your connection, it'll result in said connection consuming five times more of the network's total bandwidth than necessary. This is obviously less than ideal.

An interesting property of Bloom filters is that just like bitwise `OR` of two filters produces a new filter representing the union of the original filters' sets, the bitwise `AND` of these filters produces a filter representing the _intersection_ of the filters' sets. Delightfully, the false positive probability in this new Bloom filter is bounded above by the false positive probabilities of the originals.

In light of this observation, here's an idea: as soon as two peers connect to each other via an introduction point, they should send each other their routing Bloom filters. From these, a number of intersections can be computed.

Of course, first we should check for the trivial case where either peer's local addresses are contained in the other's one-hop filter; this would indicate (somewhat embarrassingly) that the peers are already connected over point-to-point radio but somehow failed to notice this. This will, of course, almost never happen, and so a more involved strategy may be required.

Before getting into details, let's introduce some notation. Let's call our two peers $$a$$ and $$b$$ and denote $$a$$'s one-hop filter as $$a_1$$, their two-hop filter as $$a_2$$, and so on; likewise with $$b_1$$, $$b_2$$, etc. Denote bitwise `AND` and `OR` with $$\land$$ and $$\lor$$ respectively.

The intersection of the peers' one-hop filters, $$a_1 \& b_1$$, gives the set of all addresses and address prefixes that can be reached by both peers in one hop. This set almost certainly will contain some prefixes, but it is not guaranteed to contain any full addresses. However, if the intersection _does_ contain a full-length address then the peers have identified a specific address which they are both one hop away from. This will (with overwhelming probability) mean that they have also identified a third peer who can serve as an introduction point for a minimal-length circuit between the two peers.

So how do we check whether any full addresses are contained in the intersection filter? If the full address is contained in the filter, then necessarily all prefixes of it will be as well, and so we can just run a depth-first search. This search will either terminate on a full address or determine that no such addresses are contained in the filter.

If an address is identified, the peers may attempt to look it up and establish a new connection over it. If this fails, they may search for any other addresses in the filter and try these as well.

If no addresses are found, or if all attempts to set up additional circuits over the candidate addresses fail, then the peers may move on from looking for a two-hop circuit to looking for a three-hop circuit. This means they need to find a third peer who's one hop from one peer and two hops from the other, so the Bloom filter to search here is given by $$(a_1 \land b_2) \lor (a_2 \land b_1)$$. If they find a full address here and carry out a successful rendezvous through it, great; if not, they'll need to look for a four-hop circuit, for which the filter to search will be $$(a_1 \land b_3) \lor (a_2 \land b_2) \lor (a_3 \land b_1)$$.

This process can be run until we run out of Bloom filters or until we identify enough circuits.

Given enough time, this process should allow two peers to exhaustively identify all the addresses they can both reach and to determine the minimum number of hops required to set up a circuit through any mutually visible address.


### Questions

* None of this says anything about optimizing routes based on available bandwidth on individual point-to-point connections. How could we handle that?

* For that matter, what would it take to set up these point-to-point connections in the first place?

* What sort of criteria should we adhere to with regard to setting Bloom filter parameters?

* How can we model the routing system's bandwidth overhead? It appears to meet the requirement of being $$\mathcal{O}(1)$$ with regard to network size, and it seems intuitively likely that bandwidth would decrease as the network's average path length decreases[^6], but how can we formalize these intuitions?

[^6]: My reasoning here is that in networks where many addresses can be reached with a small number of hops, peers are likely to be sending fewer total filters since they will reach their saturation cutoff more quickly.

* How much of this traffic can be encrypted?

* How much would the network benefit from adding "shortcuts" (e.g. long-distance high-bandwidth radio links between distant endpoints, or nodes which also have internet connections and use these to knit physically distant regions of the mesh together)?

* How should we manage public identities on the network? Should identities be long-lived or per-session?

* How well does this algorithm handle peer churn? How fast should the update intervals for broadcasting Bloom filter changes be? Should they scale dynamically?

As you can see, there's a lot more work to be done here to fill this idea out and get anything even resembling a full specification. That said, this routing construct feels very powerful, and I wonder if something useful could come of it.

<hr>