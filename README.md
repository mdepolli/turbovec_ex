# TurboVec

Elixir bindings for [turbovec](https://github.com/RyanCodrai/turbovec): in-process
vector search with TurboQuant compression. No training pass, no sidecar, no
graph to rebuild.

A 10 million × 1536-d float32 corpus is about 61 GB. TurboVec keeps it under
8 GB at the default 4-bit (under 4 GB at 2-bit) and searches the quantized
codes with SIMD. Think SQLite for embeddings — a function call on one node,
not Qdrant.

This is the right shape for Phoenix RAG in the roughly 50k–2M chunk range:
Broadway or Oban can `add` as chunks land, tenants filter with an allowlist
inside the kernel, and deletes by stable id are cheap (the first id lookup
after a `load/1` builds the id map once, O(n)).

It is **not** HNSW. It is exhaustive SIMD search over 2–4 bit codes. That is a
feature until a few million vectors and the wrong tool after that. It is also
not a cluster. The handle is a node-local NIF resource. Multi-node: keep
Postgres/pgvector as source of truth and treat this as a hot cache you rebuild
on boot.

v1 wraps turbovec's `IdMapIndex` only (stable `u64` ids). The low-level
positional index is out of scope.

## Installation

Add `turbovec_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:turbovec_ex, "~> 0.1.0"}
  ]
end
```

The NIF is precompiled — no Rust toolchain needed. To compile from
source, set `TURBOVEC_EX_BUILD=1` (requires Rust ≥ 1.89). 64-bit hosts
only.

Docs: <https://hexdocs.pm/turbovec_ex>.

## API

```elixir
{:ok, idx} = TurboVec.new(dim: 1536, bit_width: 4)
:ok = TurboVec.add(idx, vectors, ids)
{:ok, results} = TurboVec.search(idx, query, k: 10, allowlist: tenant_ids)
# results: [{id, score}, ...]  — length <= k, best first
:ok = TurboVec.remove(idx, id)

count = TurboVec.count(idx)
dim = TurboVec.dim(idx)
bit_width = TurboVec.bit_width(idx)
true = TurboVec.contains?(idx, id)

:ok = TurboVec.write(idx, "/var/data/myapp/index.tvim")
{:ok, idx} = TurboVec.load("/var/data/myapp/index.tvim")
:ok = TurboVec.sync(idx, "/var/data/myapp/index.tvim")
```

`bit_width` is `2`, `3`, or `4`. Default **4**. Two-bit is smaller and faster
and needs a recall measurement on _your_ embeddings; do not pick it because
the README mentioned compression.

Vectors and queries are a native-endian `f32` binary, or an `Nx.Tensor` of
type `{:f, 32}` (optional dependency). Add tensors must be `{n, dim}`. A query
is one row: binary of `4 * dim` bytes, or shape `{dim}` / `{1, dim}`. Lists of
floats are not an API.

Scores are length-renormalized **inner product**, not cosine. They match
cosine only when the vectors are L2-normalized.

`k = 0` is an error. An empty index or a tight allowlist returns fewer than
`k` hits — `length(results) <= k`.

## Persistence

`write/2` is a full durable snapshot. `sync/2` is a durable incremental
save to one path (first call to a fresh path writes the whole file).
`load/1` reads both.

Do not mix `write/2` and `sync/2` on one path as a routine workflow.
A same-handle `write` then `sync` rebuilds (the snapshot is unclaimed,
not foreign). Two handles incrementally syncing one path is not
supported — the crate notices after the fact, it does not lock.

On-disk `.tvim` is little-endian. In-memory vector binaries are native-endian.
Do not checksum one against the other.

## Tuning

Crate work runs on a dedicated rayon pool (threads named `turbovec-*`),
not the process-global pool. Size, first match wins:

1. `TURBOVEC_NUM_THREADS`
2. `RAYON_NUM_THREADS`
3. `max(1, available_parallelism / 2)`

## Constraints we will not walk back

- 64-bit only. The upstream crate will not compile otherwise.
- The index does not travel: not to another node, not through
  `:erlang.term_to_binary/1`, not in ETS across a restart. Move it with
  `write` / `load`.
- Anyone holding the term can call it. Searches overlap. Mutations take
  an exclusive lock. If you want a single owner, wrap the handle in your
  own GenServer — this library will not.
