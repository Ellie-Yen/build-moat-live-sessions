1. **Watcher vs Cron:** Why separate the watcher from the worker? What problems does a single cron job that both scans and executes have?
   resource isolation and scheduling semantics:

   Different scaling profiles. Watcher is I/O-bound (DB scans), worker is workload-bound (could be CPU, network, or AI API calls). You want to scale them independently — 1 watcher + 50 workers is normal; 50 watchers + 50 workers wastes DB.

   Different failure modes. If a worker crashes mid-execution, you don't want the watcher to lose its scan position. They have separate liveness concerns.

   Single Responsibility / observability. When something breaks, "is the watcher behind?" vs "are workers stuck?" are very different ops questions. Conflating them makes debugging painful.

   Cron's real problem isn't just "blocking":
   No visibility into in-flight work. Cron fires every N minutes regardless of whether the previous run finished. You need locking/leader election bolted on.
   No retry semantics. A cron that scans + executes either commits the whole batch or loses progress on partial failure.
   No backpressure. If 10K jobs become due at once, cron tries to execute all of them in one process.
   No fairness. A long job blocks all subsequent due jobs in that tick.

---

2. **Queue Layer:** Why put a queue between the watcher and worker instead of having the watcher call the worker directly? What are the benefits?
   Backpressure & smoothing. Watcher might dump 50K jobs in a 1-second burst at the top of the hour. Queue absorbs the spike; workers drain at their natural rate. Without it, you'd hammer downstream services.
   Delivery guarantees. A proper queue (SQS, Pub/Sub, RabbitMQ, Redis Streams) gives you at-least-once delivery, ack/nack semantics, visibility timeouts, and DLQs. Direct calls give you none of that — if the worker dies mid-call, the job is lost.
   Retry & DLQ. Failed jobs go back on the queue with backoff, or to a DLQ after N attempts. This is a huge feature you'd otherwise build yourself.
   Decoupling deployment. You can deploy/restart workers without the watcher caring. The queue is the contract.
   Routing / fan-out. Multiple worker pools can subscribe to different queues (e.g., tasks.ai, tasks.email), enabling priority and isolation.
   Location transparency. Watcher doesn't need to know where workers are or how many exist.

---

3. **Time Bucket Partitioning:** Instead of `SELECT * WHERE scheduled_at <= now()`, why partition jobs by time bucket (e.g., hour)? What happens to query performance at 1M+ jobs without partitioning?
   - What SELECT \* WHERE scheduled_at <= now() does at scale:
     Even with an index on scheduled_at, the watcher scans a growing range. As jobs accumulate, completed/old jobs that weren't cleaned up sit in the index. The query has to either filter them out (AND status = 'pending') or rely on you deleting them.
     More importantly, every watcher tick re-scans overlapping ranges. The "due" set changes slowly but the query re-evaluates from scratch.
     Index bloat over time degrades B-tree performance (you know this from your Postgres VACUUM work).
     Lock contention: if many watchers run, they fight over the same hot index pages.
   - What time bucketing actually buys you:
     Bounded scan size per tick. Watcher only queries bucket = '2026-05-10T14'. Each bucket has a known max size. You're not scanning history.
     Natural sharding/parallelism. Different watchers can own different buckets. No coordination needed.
     Cheap cleanup. Drop old bucket partitions wholesale (Postgres native partitioning, BigQuery partition expiration). No expensive DELETE scans.
     Cache-friendly. The "current bucket" fits in memory; the index for it is hot.
     Predictable query plans. Partition pruning makes the planner's job trivial.

---

4. **Tool Naming:** Why `task.create` instead of `createTask`? How does naming convention affect LLM tool selection accuracy?
   Discoverability and grouping. When the LLM sees task.create, task.list, task.cancel, task.status together, the namespace acts as a semantic cluster. The model learns "for task operations, look at task.\*." With createTask, listTasks, cancelTask, the prefix changes per operation and the relationship is less explicit.
   Disambiguation across domains. In a multi-tool MCP server, you might have task.create, user.create, webhook.create. The dotted namespace makes it obvious these are parallel operations on different resources. createTask/createUser/createWebhook works too but doesn't scale as cleanly.
   Convention matching. LLMs are trained on tons of code where noun.verb (method calls) is overwhelmingly common — db.query, user.save, client.send. The model has strong priors on this pattern. Function-name style (createTask) competes with REST/RPC conventions.
   Programmatic routing. Server-side, task.create parses cleanly into (namespace, action) for registry dispatch (which connects to Q5).

---

5. **Registry vs If-Else:** Why use a dictionary registry to route tool calls instead of if-else chains? What happens when you need to add the 20th tool?
   Open/Closed Principle. Adding the 20th tool with if-else means modifying the dispatch function (risk: breaking the other 19). With a registry, you registry["task.archive"] = handler and the dispatcher is untouched. This is the textbook reason and what the question is really fishing for.
   Plugin architecture. A registry lets tools self-register at import time (decorator pattern: @register("task.create")). Each tool lives in its own module. With if-else, all tools must be imported and referenced in one giant function.
   Runtime introspection. registry.keys() is your tool list — used for MCP's tools/list endpoint, for help text, for validation. With if-else, you have to maintain a parallel list and they drift.
   Testability. You can mock the registry, inject test handlers, swap implementations. If-else is a closed black box.
   Performance at scale. Dict lookup is O(1). If-else is O(n). At 20 tools this is irrelevant; at 200 it starts to matter, but more importantly, branch prediction and cache behavior of long if-else chains is bad.
   Dynamic registration. Tools could be registered from plugins, config files, or even user-defined code. If-else can't do this.
