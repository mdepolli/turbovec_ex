mod error;

use rustler::{Binary, Error, NifResult, Resource, ResourceArc, Term};
use std::borrow::Cow;
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

// Non-integer -> BadArg (raises ArgumentError in Elixir).
// Integer outside u64 -> {:error, {:id_out_of_range, id}}.
fn decode_ids(terms: Vec<Term>) -> NifResult<Vec<u64>> {
    terms
        .into_iter()
        .map(|t| {
            if let Ok(id) = t.decode::<u64>() {
                Ok(id)
            } else if let Ok(big) = t.decode::<i128>() {
                Err(Error::Term(Box::new((
                    error::atoms::id_out_of_range(),
                    big,
                ))))
            } else {
                Err(Error::BadArg)
            }
        })
        .collect()
}

// Zero-copy when the binary is 4-byte aligned; copy fallback otherwise.
fn f32s<'a>(bin: &'a Binary) -> Cow<'a, [f32]> {
    match bytemuck::try_cast_slice(bin.as_slice()) {
        Ok(slice) => Cow::Borrowed(slice),
        Err(_) => Cow::Owned(
            bin.as_slice()
                .chunks_exact(4)
                .map(|c| f32::from_ne_bytes(c.try_into().unwrap()))
                .collect(),
        ),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn add(
    res: ResourceArc<IndexResource>,
    vectors: Binary,
    ids: Vec<Term>,
) -> NifResult<rustler::Atom> {
    if vectors.len() % 4 != 0 {
        return Err(Error::Term(Box::new((
            error::atoms::vector_byte_size_mismatch(),
            vectors.len(),
        ))));
    }
    let ids = decode_ids(ids)?;
    let vecs = f32s(&vectors);
    let mut idx = write(&res);
    idx.add_with_ids(&vecs, &ids).map_err(error::add)?;
    Ok(error::atoms::ok())
}

rustler::init!("Elixir.TurboVec.NIF");
