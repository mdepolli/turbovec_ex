mod error;
mod pool;

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
    if !vectors.len().is_multiple_of(4) {
        return Err(Error::Term(Box::new((
            error::atoms::vector_byte_size_mismatch(),
            vectors.len(),
        ))));
    }
    let ids = decode_ids(ids)?;
    let vecs = f32s(&vectors);
    let mut guard = write(&res);
    let idx: &mut IdMapIndex = &mut guard;
    pool::get()
        .install(|| idx.add_with_ids(&vecs, &ids))
        .map_err(error::add)?;
    Ok(error::atoms::ok())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn remove(res: ResourceArc<IndexResource>, id: Term) -> NifResult<rustler::Atom> {
    let id = decode_ids(vec![id])?[0];
    let mut guard = write(&res);
    let idx: &mut IdMapIndex = &mut guard;
    if pool::get().install(|| idx.remove(id)) {
        Ok(error::atoms::ok())
    } else {
        Err(Error::Term(Box::new(error::atoms::not_found())))
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn search(
    res: ResourceArc<IndexResource>,
    query: Binary,
    k: usize,
    allowlist: Option<Vec<Term>>,
) -> NifResult<Vec<(u64, f32)>> {
    if k < 1 {
        return Err(Error::Term(Box::new((error::atoms::invalid_k(), k))));
    }
    let allow = allowlist.map(decode_ids).transpose()?;
    let query_f32s = f32s(&query);
    let idx = read(&res);
    // Exactly one row: a multi-row buffer would silently flatten a batch (spec).
    let dim = idx.dim_opt().expect("index is always dim-committed");
    if query.len() != 4 * dim {
        return Err(Error::Term(Box::new((
            error::atoms::query_size_mismatch(),
            4 * dim,
            query.len(),
        ))));
    }
    let results = pool::get()
        .install(|| idx.try_search_with_allowlist(&query_f32s, k, allow.as_deref()))
        .map_err(error::search)?;
    Ok(results
        .ids_for_query(0)
        .iter()
        .copied()
        .zip(results.scores_for_query(0).iter().copied())
        .collect())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn contains(res: ResourceArc<IndexResource>, id: u64) -> bool {
    let idx = read(&res);
    pool::get().install(|| idx.contains(id))
}

#[rustler::nif(schedule = "DirtyIo")]
fn write_index(res: ResourceArc<IndexResource>, path: String) -> NifResult<rustler::Atom> {
    let idx = read(&res);
    pool::get()
        .install(|| idx.write(&path))
        .map_err(error::io)?;
    Ok(error::atoms::ok())
}

#[rustler::nif(schedule = "DirtyIo")]
fn sync(res: ResourceArc<IndexResource>, path: String) -> NifResult<rustler::Atom> {
    let mut guard = write(&res);
    let idx: &mut IdMapIndex = &mut guard;
    pool::get().install(|| idx.sync(&path)).map_err(error::io)?;
    Ok(error::atoms::ok())
}

#[rustler::nif(schedule = "DirtyIo")]
fn load(path: String) -> NifResult<ResourceArc<IndexResource>> {
    let idx = pool::get()
        .install(|| IdMapIndex::load(&path))
        .map_err(error::io)?;
    if idx.dim_opt().is_none() {
        // Spec: reject lazy loads so add_with_ids' documented panic is unreachable
        return Err(Error::Term(Box::new(error::atoms::uncommitted_dim())));
    }
    Ok(ResourceArc::new(IndexResource(RwLock::new(idx))))
}

rustler::init!("Elixir.TurboVec.NIF");
