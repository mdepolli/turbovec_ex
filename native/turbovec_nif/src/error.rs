use rustler::Error;
use turbovec::{AddError, ConstructError};

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
