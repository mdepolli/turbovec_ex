// One-off generator: cargo test --manifest-path native/turbovec_nif/Cargo.toml \
//   --test fixtures -- --ignored
#[test]
#[ignore]
fn write_lazy_fixture() {
    let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/../../test/fixtures");
    std::fs::create_dir_all(dir).unwrap();
    let idx = turbovec::IdMapIndex::new_lazy(4).unwrap();
    idx.write(format!("{dir}/lazy.tvim")).unwrap();
}
