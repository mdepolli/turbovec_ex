use rustler::Error;
use turbovec::{AddError, ConstructError, SearchError};

pub mod atoms {
    rustler::atoms! {
        ok,
        invalid_bit_width,
        invalid_dim,
        dim_too_large,
        dim_mismatch,
        vector_buffer_size_mismatch,
        vector_byte_size_mismatch,
        ids_count_mismatch,
        id_already_present,
        duplicate_id_in_batch,
        invalid_input_value,
        id_out_of_range,
        allowlist_empty,
        unknown_id,
        invalid_query_value,
        invalid_k,
        query_size_mismatch,
        not_found,
        uncommitted_dim,
        io_error,
        permission_denied,
        invalid_data,
        already_exists,
        other,
        turbovec_error,
    }
}

pub fn construct(e: ConstructError) -> Error {
    match e {
        ConstructError::BitWidthOutOfRange(bw) => {
            Error::Term(Box::new((atoms::invalid_bit_width(), bw)))
        }
        ConstructError::DimNotPositiveMultipleOf8(d) => {
            Error::Term(Box::new((atoms::invalid_dim(), d)))
        }
        ConstructError::DimTooLarge { dim, max } => {
            Error::Term(Box::new((atoms::dim_too_large(), dim, max)))
        }
        // #[non_exhaustive]: future variants must not break our compile
        other => Error::Term(Box::new((atoms::turbovec_error(), other.to_string()))),
    }
}

pub fn add(e: AddError) -> Error {
    match e {
        AddError::DimMismatch { existing, got } => {
            Error::Term(Box::new((atoms::dim_mismatch(), existing, got)))
        }
        AddError::DimNotMultipleOf8(d) => Error::Term(Box::new((atoms::invalid_dim(), d))),
        AddError::DimTooLarge { dim, max } => {
            Error::Term(Box::new((atoms::dim_too_large(), dim, max)))
        }
        AddError::ZeroDim => Error::Term(Box::new((atoms::invalid_dim(), 0usize))),
        AddError::VectorBufferNotMultipleOfDim { vectors_len, dim } => Error::Term(Box::new((
            atoms::vector_buffer_size_mismatch(),
            vectors_len,
            dim,
        ))),
        AddError::IdsCountMismatch { expected, got } => {
            Error::Term(Box::new((atoms::ids_count_mismatch(), expected, got)))
        }
        AddError::IdAlreadyPresent(id) => Error::Term(Box::new((atoms::id_already_present(), id))),
        AddError::DuplicateIdInBatch(id) => {
            Error::Term(Box::new((atoms::duplicate_id_in_batch(), id)))
        }
        AddError::InvalidInputValue {
            vector_index,
            coord_index,
            value,
        } => Error::Term(Box::new((
            atoms::invalid_input_value(),
            vector_index,
            coord_index,
            value.to_string(),
        ))),
        other => Error::Term(Box::new((atoms::turbovec_error(), other.to_string()))),
    }
}

pub fn search(e: SearchError) -> Error {
    match e {
        SearchError::AllowlistEmpty => Error::Term(Box::new(atoms::allowlist_empty())),
        SearchError::UnknownId(id) => Error::Term(Box::new((atoms::unknown_id(), id))),
        // query_index dropped: always 0 in the single-query API (spec)
        SearchError::InvalidQueryValue {
            coord_index, value, ..
        } => Error::Term(Box::new((
            atoms::invalid_query_value(),
            coord_index,
            value.to_string(),
        ))),
        other => Error::Term(Box::new((atoms::turbovec_error(), other.to_string()))),
    }
}

pub fn io(e: std::io::Error) -> Error {
    use std::io::ErrorKind::*;
    let kind = match e.kind() {
        NotFound => atoms::not_found(),
        PermissionDenied => atoms::permission_denied(),
        InvalidData => atoms::invalid_data(),
        AlreadyExists => atoms::already_exists(),
        _ => atoms::other(),
    };
    Error::Term(Box::new((atoms::io_error(), kind, e.to_string())))
}
