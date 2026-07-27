# Failure Matrix

Lab 09's deliverable. See [`labs/09-failure-matrix.md`](labs/09-failure-matrix.md)
for the method.

Write the **prediction** before running the fault. That column is the point.

Setup for every row:

* a browser tab open on a channel, watched while the fault lands
* `mix beamslack.loadtest --clients 20 --rate 2 --duration 60` running
* the server started with `bin/dev-node.sh a`, so `mix beamslack.kill` can reach it
* the server log visible

---

## 1. Kill a channel runtime

**Fault:** kill the `ChannelRuntime` for a channel with users connected.

| | |
| --- | --- |
| Prediction | |
| What died | |
| Who noticed | |
| What restarted it | |
| How long | |
| State lost | |
| User saw | |
| **Layer that recovered it** | |

Notes:

---

## 2. Kill the Presence tracker

**Fault:** `mix beamslack.kill presence`

| | |
| --- | --- |
| Prediction | |
| What died | |
| Who noticed | |
| What restarted it | |
| How long | |
| State lost | |
| User saw | |
| **Layer that recovered it** | |

Notes: follow the whole chain in the log. First crash, then every `failed to
start`, then whatever ended it.

---

## 3. Kill PubSub

**Fault:** `mix beamslack.kill pubsub`

| | |
| --- | --- |
| Prediction | |
| What died | |
| Who noticed | |
| What restarted it | |
| How long | |
| State lost | |
| User saw | |
| **Layer that recovered it** | |

Notes: what happened to existing subscriptions? Did anything re-subscribe, and if
so, what triggered it?

---

## 4. Kill the Endpoint

**Fault:** `mix beamslack.kill endpoint`

| | |
| --- | --- |
| Prediction | |
| What died | |
| Who noticed | |
| What restarted it | |
| How long | |
| State lost | |
| User saw | |
| **Layer that recovered it** | |

Notes: separate the HTTP answer from the WebSocket answer. They are not the same.

---

## 5. Kill the Repo

**Fault:** `mix beamslack.kill repo`

| | |
| --- | --- |
| Prediction | |
| What died | |
| Who noticed | |
| What restarted it | |
| How long | |
| State lost | |
| User saw | |
| **Layer that recovered it** | |

Notes:

---

## 6. Drop every database connection

**Fault:** `curl -X POST localhost:4000/dev/faults/db`

| | |
| --- | --- |
| Prediction | |
| What died | |
| Who noticed | |
| What restarted it | |
| How long | |
| State lost | |
| User saw | |
| **Layer that recovered it** | |

Notes: how does this differ from row 5? If it does not, look harder — the
connection processes are not children of the Repo supervisor.

---

## 7. Stop PostgreSQL

**Fault:** `docker compose stop postgres`, wait, then `docker compose start postgres`

| | |
| --- | --- |
| Prediction | |
| What died | |
| Who noticed | |
| What restarted it | |
| How long | |
| State lost | |
| User saw | |
| **Layer that recovered it** | |

Notes: which parts of the app kept working, and what does that say about where
state lives? Watch for `db pool saturated` in the log before anything errors.

---

## 8. Kill one socket process

**Fault:** find a socket process on the dashboard's Processes page, kill it from IEx.

| | |
| --- | --- |
| Prediction | |
| What died | |
| Who noticed | |
| What restarted it | |
| How long | |
| State lost | |
| User saw | |
| **Layer that recovered it** | |

Notes: is a socket process supervised? Should it be? What is the argument for
letting it stay dead?

---

## 9. Flood a process

**Fault:** `mix beamslack.flood --count 100000 --watch`

| | |
| --- | --- |
| Prediction | |
| What died | |
| Who noticed | |
| What restarted it | |
| How long | |
| State lost | |
| User saw | |
| **Layer that recovered it** | |

Notes: nothing crashed, so which column is even applicable? That is the finding.

---

## 10. Kill the rate limiter's ETS owner

**Fault:** see Lab 07.

| | |
| --- | --- |
| Prediction | |
| What died | |
| Who noticed | |
| What restarted it | |
| How long | |
| State lost | |
| User saw | |
| **Layer that recovered it** | |

Notes:

---

## 11. Kill the Watcher with watches outstanding

**Fault:** see Lab 06.

| | |
| --- | --- |
| Prediction | |
| What died | |
| Who noticed | |
| What restarted it | |
| How long | |
| State lost | |
| User saw | |
| **Layer that recovered it** | |

Notes: who now knows about the processes that were being watched?

---

## 12. Kill the VM

**Fault:** `kill -9` the beam process, then restart it.

| | |
| --- | --- |
| Prediction | |
| What died | |
| Who noticed | |
| What restarted it | |
| How long | |
| State lost | |
| User saw | |
| **Layer that recovered it** | |

Notes: the control group. Whatever came back is your empirical definition of
durable.

---

## Conclusions

Which layer does the most work?

Which layer did you think was doing the most work before starting?

Where were your predictions wrong, and why?
