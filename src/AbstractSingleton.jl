import Base.∈

export AbstractSingleton,
       element,
       an_element,
       linear_map

"""
    AbstractSingleton{N<:Real} <: AbstractHyperrectangle{N}

Abstract type for sets with a single value.

### Notes

Every concrete `AbstractSingleton` must define the following functions:
- `element(::AbstractSingleton{N})::Vector{N}` -- return the single element
- `element(::AbstractSingleton{N}, i::Int)::N` -- return the single element's
    entry in the `i`-th dimension

```jldoctest
julia> subtypes(AbstractSingleton)
2-element Array{Any,1}:
 Singleton
 ZeroSet
```
"""
abstract type AbstractSingleton{N<:Real} <: AbstractHyperrectangle{N} end


# --- AbstractHyperrectangle interface functions ---


"""
    radius_hyperrectangle(S::AbstractSingleton{N}, i::Int)::N where {N<:Real}

Return the box radius of a set with a single value in a given dimension.

### Input

- `S` -- set with a single value
- `i` -- dimension of interest

### Output

Zero.
"""
function radius_hyperrectangle(S::AbstractSingleton{N}, i::Int
                              )::N where {N<:Real}
    return zero(N)
end


"""
    radius_hyperrectangle(S::AbstractSingleton{N})::Vector{N} where {N<:Real}

Return the box radius of a set with a single value in every dimension.

### Input

- `S` -- set with a single value

### Output

The zero vector.
"""
function radius_hyperrectangle(S::AbstractSingleton{N}
                              )::Vector{N} where {N<:Real}
    return zeros(N, dim(S))
end


"""
    high(S::AbstractSingleton{N})::Vector{N} where {N<:Real}

Return the higher coordinates of a set with a single value.

### Input

- `S` -- set with a single value

### Output

A vector with the higher coordinates of the set with a single value.
"""
function high(S::AbstractSingleton{N})::Vector{N} where {N<:Real}
    return element(S)
end

"""
    high(S::AbstractSingleton{N}, i::Int)::N where {N<:Real}

Return the higher coordinate of a set with a single value in the given
dimension.

### Input

- `S` -- set with a single value
- `i` -- dimension of interest

### Output

The higher coordinate of the set with a single value in the given dimension.
"""
function high(S::AbstractSingleton{N}, i::Int)::N where {N<:Real}
    return element(S)[i]
end

"""
    low(S::AbstractSingleton{N})::Vector{N} where {N<:Real}

Return the lower coordinates of a set with a single value.

### Input

- `S` -- set with a single value

### Output

A vector with the lower coordinates of the set with a single value.
"""
function low(S::AbstractSingleton{N})::Vector{N} where {N<:Real}
    return element(S)
end

"""
    low(S::AbstractSingleton{N}, i::Int)::N where {N<:Real}

Return the lower coordinate of a set with a single value in the given
dimension.

### Input

- `S` -- set with a single value
- `i` -- dimension of interest

### Output

The lower coordinate of the set with a single value in the given dimension.
"""
function low(S::AbstractSingleton{N}, i::Int)::N where {N<:Real}
    return element(S)[i]
end



# --- AbstractCentrallySymmetric interface functions ---


"""
    center(S::AbstractSingleton{N})::Vector{N} where {N<:Real}

Return the center of a set with a single value.

### Input

- `S` -- set with a single value

### Output

The only element of the set.
"""
function center(S::AbstractSingleton{N})::Vector{N} where {N<:Real}
    return element(S)
end


# --- AbstractPolytope interface functions ---


"""
    vertices_list(S::AbstractSingleton{N})::Vector{Vector{N}} where {N<:Real}

Return the list of vertices of a set with a single value.

### Input

- `S` -- set with a single value

### Output

A list containing only a single vertex.
"""
function vertices_list(S::AbstractSingleton{N}
                      )::Vector{Vector{N}} where {N<:Real}
    return [element(S)]
end

"""
    linear_map(M::AbstractMatrix{N}, S::AbstractSingleton{N}) where {N<:Real}

Concrete linear map of an abstract singleton.

### Input

- `M` -- matrix
- `S` -- abstract singleton

### Output

The abstract singleton of the same type of ``S`` obtained by applying the
linear map to the element in ``S``.
"""
function linear_map(M::AbstractMatrix{N},
                    S::AbstractSingleton{N}) where {N<:Real}
    @assert dim(S) == size(M, 2) "a linear map of size $(size(M)) cannot be " *
                                 "applied to a set of dimension $(dim(S))"

    T = typeof(S)
    return T(M * element(S))
end

# --- LazySet interface functions ---


"""
    σ(d::AbstractVector{N}, S::AbstractSingleton{N}) where {N<:Real}

Return the support vector of a set with a single value.

### Input

- `d` -- direction
- `S` -- set with a single value

### Output

The support vector, which is the set's vector itself, irrespective of the given
direction.
"""
function σ(d::AbstractVector{N}, S::AbstractSingleton{N}) where {N<:Real}
    return element(S)
end


"""
    ∈(x::AbstractVector{N}, S::AbstractSingleton{N})::Bool where {N<:Real}

Check whether a given point is contained in a set with a single value.

### Input

- `x` -- point/vector
- `S` -- set with a single value

### Output

`true` iff ``x ∈ S``.

### Notes

This implementation performs an exact comparison, which may be insufficient with
floating point computations.
"""
function ∈(x::AbstractVector{N}, S::AbstractSingleton{N})::Bool where {N<:Real}
    return x == element(S)
end
