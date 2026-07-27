# Lab 11 — Kill a Node and Attribute the Recovery

Track 4. Concepts: `{:nodedown, node}`, `net_ticktime`, client reconnect, Presence
convergence after a node loss, what "highly available" actually costs.

## The problem

Lab 09 built a failure matrix for one node. This is the same discipline applied to
losing a whole one, and the attribution is harder because more layers are involved
and they recover on very different timescales:

* OTP notices in **milliseconds** if the node was cleanly stopped, and in **up to
  four minutes** if it went silent, because `net_ticktime` defaults to 60 seconds
  and a peer is declared down after roughly four intervals
* Phoenix.Presence prunes the departed node's entries after its own
  `down_period`, which is not the same number
* the JavaScript client reconnects on its own backoff schedule, which is a third
  number
* PostgreSQL does not care at all, and every message ever sent is still there

Users experience the maximum of those, not the minimum. Knowing which one dominates
is the difference between a real availability story and a hopeful one.

## Setup

```
bin/dev-node.sh a
bin/dev-node.sh b
mix beamslack.cluster connect
```

Two browsers, one on each node:

```
npm run dev:a     # http://localhost:5173, talks to node a
npm run dev:b     # http://localhost:5174, talks to node b
```

Log in as different users in each, open the same channel, and confirm they can see
each other's messages and presence. The HealthBadge shows which node each session
is on, and `+1` next to it means that node currently sees a peer.

Also useful: `mix beamslack.loadtest --clients 20 --rate 2 --duration 120 --url
http://localhost:4001` so node B has real traffic when it dies.

## The experiments

Run each one twice: once predicting first and writing it down, once watching
closely. Record the answers in `docs/failure-matrix.md` alongside Lab 09's rows.

### 1. Clean stop

Ctrl-C node B twice, letting the VM shut down normally.

* How long before node A's `Node.list/0` no longer includes it?
* What did the browser on node A see? Did presence for node B's users disappear,
  and how quickly?
* What did the browser on node B see, and how long did it take to notice?
* Did node B's user's messages survive? Where were they?

### 2. Hard kill

`kill -9` node B's beam process.

* Is the timing different from the clean stop? Why? What did the clean stop do that
  a `kill -9` cannot? (This is the whole reason both experiments exist.)
* Which mechanism told node A this time?

### 3. Silence without death

`kill -STOP` node B's beam. The process is frozen: not dead, not answering, its TCP
connections still open.

* How long until node A declares it down? Predict from `net_ticktime` first.
* During the wait, what does node A believe? What do requests that need node B do?
* Now `kill -CONT` it before the tick expires. What does node B think happened?
  Does it know it was frozen?

This is the most realistic failure of the three and the least like what people
imagine when they say "the node went down".

### 4. Come back

Restart node B and reconnect it.

* Do node B's old presence entries return? Should they?
* Does the browser that was on node B reconnect on its own, or does it need a
  reload?
* Does node A's view converge, and how long does it take?
* Is there any state that is now permanently wrong on either node? Look for it
  rather than assuming there is not.

### 5. Kill the node the load test is pointed at

With `mix beamslack.loadtest` running against node B, kill node B.

* What does the load test report? Does it reconnect?
* Do the messages it had already sent exist in the database?
* Were any accepted and lost? How would you know? (Notice this is Lab 02's
  ordering question arriving with real consequences.)

## The seven questions, per experiment

Same as Lab 09. What died, who noticed, what restarted it, how long, what state
was lost, what the user saw, and **which layer actually recovered it**.

Add one more for this lab: **what number governed the timing?** Every recovery
above is dominated by a specific configured value. Name it, find where it is set,
and say what would change if you halved it.

## Failure questions

1. `net_ticktime` defaults to 60 seconds and detection takes about four intervals.
   Why is the default so high? What breaks if you set it to 5?
2. A pid on node A refers to a process on node B, and node B dies. What does
   `Process.alive?/1` return for it? What does sending to it do?
3. A `GenServer.call/3` is in flight to node B when it dies. What does the caller
   get, and after how long? Which timeout wins?
4. Presence eventually removes node B's users. What is the mechanism —
   `Phoenix.Tracker`'s `down_period` or its `permdown_period`? They are very
   different numbers with different meanings. Look them up and say which applies to
   which experiment above.
5. Node B is restarted with the same name. Is it the same node as far as `:global`,
   `:pg`, and Presence are concerned? Each one answers differently.

## Acceptance criteria

* Five experiments recorded in `docs/failure-matrix.md`, predictions written first.
* For each, the governing timeout named and located.
* One sentence: what is the worst-case time between "a node dies" and "every user
  is served correctly again", and which layer is the bottleneck?
* At least one prediction you got wrong. Experiment 3 usually supplies it.

## Non-goals

* No automatic failover, no leader election, no load balancer.
* No tuning. Measure the defaults first; a number you changed before understanding
  is a number you cannot reason about.
* Do not fix anything you find. Note it, finish the matrix, then decide.

## Hints

* `:net_kernel.set_net_ticktime/1` changes the tick at runtime, and every node in
  the cluster must agree or they will disconnect each other. Try it *after*
  measuring the default.
* `Node.monitor(node, true)` then `receive do {:nodedown, n} -> ...` in IEx is the
  cleanest way to time detection precisely.
* `kill -STOP` and `kill -CONT` are the closest you can get to a partition without
  touching the network, and they are more realistic than either a clean stop or a
  `kill -9`.
* The browser's reconnect backoff is in `frontend/src/realtime/socket.ts`, in the
  Phoenix JS client's defaults. Know the number before you time it.
