use std::sync::OnceLock;

static POOL: OnceLock<rayon::ThreadPool> = OnceLock::new();
static DEFAULT_INPUT: OnceLock<usize> = OnceLock::new();

// TURBOVEC_NUM_THREADS > RAYON_NUM_THREADS > max(1, n/2)  (spec)
// Outer max: rayon treats num_threads(0) as "auto = all cores" — a user
// asking for minimal parallelism must not silently get maximal.
pub fn pool_size(
    turbovec_env: Option<usize>,
    rayon_env: Option<usize>,
    fallback_n: usize,
) -> usize {
    std::cmp::max(
        1,
        turbovec_env.or(rayon_env).unwrap_or_else(|| fallback_n / 2),
    )
}

fn env_usize(name: &str) -> Option<usize> {
    std::env::var(name).ok().and_then(|v| v.parse().ok())
}

/// Records the dirty-CPU-scheduler count from Application.start/2.
/// Feeds only tier 3 — env vars always win (spec).
pub fn init(n: usize) {
    let _ = DEFAULT_INPUT.set(n);
}

pub fn get() -> &'static rayon::ThreadPool {
    POOL.get_or_init(|| {
        let fallback = DEFAULT_INPUT.get().copied().unwrap_or_else(|| {
            std::thread::available_parallelism()
                .map(|n| n.get())
                .unwrap_or(2)
        });
        let size = pool_size(
            env_usize("TURBOVEC_NUM_THREADS"),
            env_usize("RAYON_NUM_THREADS"),
            fallback,
        );
        rayon::ThreadPoolBuilder::new()
            .num_threads(size)
            // Named so the tripwire test can tell ours from global rayon-* (spec)
            .thread_name(|index| format!("turbovec-{index}"))
            .build()
            .expect("failed to build turbovec rayon pool")
    })
}

#[cfg(test)]
mod tests {
    use super::pool_size;

    #[test]
    fn turbovec_var_wins() {
        assert_eq!(pool_size(Some(3), Some(9), 16), 3);
    }

    #[test]
    fn rayon_var_is_second() {
        assert_eq!(pool_size(None, Some(9), 16), 9);
    }

    #[test]
    fn default_halves_and_floors_at_one() {
        assert_eq!(pool_size(None, None, 16), 8);
        assert_eq!(pool_size(None, None, 1), 1);
        assert_eq!(pool_size(None, None, 0), 1);
    }

    #[test]
    fn explicit_zero_clamps_to_one_not_auto() {
        assert_eq!(pool_size(Some(0), None, 16), 1);
        assert_eq!(pool_size(None, Some(0), 16), 1);
    }
}
