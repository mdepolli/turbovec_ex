mod error;

use rustler::{NifResult, Resource, ResourceArc};
use std::sync::{RwLock, RwLockReadGuard, RwLockWriteGuard};
use turbovec::IdMapIndex;

pub struct IndexResource(pub RwLock<IdMapIndex>);

#[rustler::resource_impl]
impl Resource for IndexResource {}

// Poison recovery on every acquisition (spec: one panic must not brick the
// handle; upstream guarantees error atomicity but not panic atomicity).
fn read(res: &IndexResource) -> RwLockReadGuard<'_, IdMapIndex> {
    res.0.read().unwrap_or_else(|p| p.into_inner())
}

fn write(res: &IndexResource) -> RwLockWriteGuard<'_, IdMapIndex> {
    res.0.write().unwrap_or_else(|p| p.into_inner())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn new(dim: usize, bit_width: usize) -> NifResult<ResourceArc<IndexResource>> {
    let idx = IdMapIndex::new(dim, bit_width).map_err(error::construct)?;
    Ok(ResourceArc::new(IndexResource(RwLock::new(idx))))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn count(res: ResourceArc<IndexResource>) -> usize {
    read(&res).len()
}

#[rustler::nif(schedule = "DirtyCpu")]
fn bit_width(res: ResourceArc<IndexResource>) -> usize {
    read(&res).bit_width()
}

#[rustler::nif(schedule = "DirtyCpu")]
fn dim(res: ResourceArc<IndexResource>) -> usize {
    // dim_opt is always Some: new/1 requires dim and load/1 rejects lazy
    // files (Task 8). Never call the deprecated dim() — 0-for-lazy footgun.
    read(&res).dim_opt().expect("index is always dim-committed")
}

rustler::init!("Elixir.TurboVec.NIF");
