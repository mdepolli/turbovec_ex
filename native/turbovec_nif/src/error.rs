use rustler::Error;
use turbovec::ConstructError;

pub mod atoms {
    rustler::atoms! {
        ok,
        invalid_bit_width,
        invalid_dim,
        dim_too_large,
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
