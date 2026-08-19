# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- In-process `IdMapIndex` binding: `new/1`, `add/3`, `remove/2`,
  `search/3`, `contains?/2`, `count/1`, `dim/1`, `bit_width/1`.
- Persistence via `write/2` (full snapshot), `sync/2` (incremental),
  and `load/1`.
- Optional `Nx.Tensor` input (`{:f, 32}`) without requiring Nx at
  compile time.
- Precompiled NIFs through `rustler_precompiled`; set
  `TURBOVEC_EX_BUILD=1` to compile from source (Rust ≥ 1.89, 64-bit).
- Dedicated rayon pool sized by `TURBOVEC_NUM_THREADS`, then
  `RAYON_NUM_THREADS`, then `max(1, available_parallelism / 2)`.
