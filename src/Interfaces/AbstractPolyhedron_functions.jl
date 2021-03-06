import Base.∈

export constrained_dimensions,
       tosimplehrep,
       remove_redundant_constraints,
       remove_redundant_constraints!,
       linear_map,
       chebyshev_center

# default LP solver for floating-point numbers
function default_lp_solver(N::Type{<:AbstractFloat})
    GLPKSolverLP(method=:Simplex)
end

# default LP solver for rational numbers
function default_lp_solver(N::Type{<:Rational})
    GLPKSolverLP(method=:Exact)
end

# fallback method
function default_polyhedra_backend(P, N)
    require(:Polyhedra; fun_name="default_polyhedra_backend")
    error("no default backend for numeric type $N")
end

"""
    ∈(x::AbstractVector{N}, P::AbstractPolyhedron{N})::Bool where {N<:Real}

Check whether a given point is contained in a polyhedron.

### Input

- `x` -- point/vector
- `P` -- polyhedron

### Output

`true` iff ``x ∈ P``.

### Algorithm

This implementation checks if the point lies inside each defining half-space.
"""
function ∈(x::AbstractVector{N}, P::AbstractPolyhedron{N})::Bool where {N<:Real}
    @assert length(x) == dim(P) "a $(length(x))-dimensional point cannot be " *
        "an element of a $(dim(P))-dimensional set"

    for c in constraints_list(P)
        if dot(c.a, x) > c.b
            return false
        end
    end
    return true
end

"""
    constrained_dimensions(P::AbstractPolyhedron)::Vector{Int} where {N<:Real}

Return the indices in which a polyhedron is constrained.

### Input

- `P` -- polyhedron

### Output

A vector of ascending indices `i` such that the polyhedron is constrained in
dimension `i`.

### Examples

A 2D polyhedron with constraint ``x1 ≥ 0`` is constrained in dimension 1 only.
"""
function constrained_dimensions(P::AbstractPolyhedron)::Vector{Int}
    constraints = constraints_list(P)
    if isempty(constraints)
        return Int[]
    end
    zero_indices = zeros(Int, dim(P))
    for constraint in constraints
        for i in constrained_dimensions(constraint)
            zero_indices[i] = i
        end
    end
    return filter(x -> x != 0, zero_indices)
end

"""
    tosimplehrep(constraints::AbstractVector{LC})
        where {N<:Real, LC<:LinearConstraint{N}}

Return the simple H-representation ``Ax ≤ b`` from a list of linear constraints.

### Input

- `constraints` -- a list of linear constraints

### Output

The tuple `(A, b)` where `A` is the matrix of normal directions and `b` is the
vector of offsets.
"""
function tosimplehrep(constraints::AbstractVector{LC}
                     ) where {N<:Real, LC<:LinearConstraint{N}}
    n = length(constraints)
    if n == 0
        A = Matrix{N}(undef, 0, 0)
        b = Vector{N}(undef, 0)
        return (A, b)
    end
    A = zeros(N, n, dim(first(constraints)))
    b = zeros(N, n)
    @inbounds begin
        for (i, Pi) in enumerate(constraints)
            A[i, :] = Pi.a
            b[i] = Pi.b
        end
    end
    return (A, b)
end

"""
     remove_redundant_constraints!(
         constraints::AbstractVector{<:LinearConstraint{N}};
         [backend]=default_lp_solver(N))::Bool where {N<:Real}

Remove the redundant constraints of a given list of linear constraints; the list
is updated in-place.

### Input

- `constraints` -- list of constraints
- `backend`     -- (optional, default: `default_lp_solver(N)`) the backend used
                   to solve the linear program
### Output

`true` if the function was successful and the list of constraints `constraints`
is modified by removing the redundant constraints, and `false` only if the
constraints are infeasible.

### Notes

Note that the result may be `true` even if the constraints are infeasible.
For example, ``x ≤ 0 && x ≥ 1`` will return `true` without removing any
constraint.
To check if the constraints are infeasible, use
`isempty(HPolyhedron(constraints)`.

### Algorithm

If there are `m` constraints in `n` dimensions, this function checks one by one
if each of the `m` constraints is implied by the remaining ones.

To check if the `k`-th constraint is redundant, an LP is formulated using the
constraints that have not yet being removed.
If, at an intermediate step, it is detected that a subgroup of the constraints
is infeasible, this function returns `false`.
If the calculation finished successfully, this function returns `true`.

For details, see [Fukuda's Polyhedra
FAQ](https://www.cs.mcgill.ca/~fukuda/soft/polyfaq/node24.html).
"""
function remove_redundant_constraints!(
        constraints::AbstractVector{<:LinearConstraint{N}};
        backend=default_lp_solver(N))::Bool where {N<:Real}

    A, b = tosimplehrep(constraints)
    m, n = size(A)
    non_redundant_indices = 1:m

    i = 1 # counter over reduced constraints

    for j in 1:m    # loop over original constraints
        α = A[j, :]
        Ar = A[non_redundant_indices, :]
        br = b[non_redundant_indices]
        br[i] = b[j] + one(N)
        lp = linprog(-α, Ar, '<', br, -Inf, Inf, backend)
        if lp.status == :Infeasible
            # the polyhedron is empty
            return false
        elseif lp.status == :Optimal
            objval = -lp.objval
            if _leq(objval, b[j])
                # the constraint is redundant
                non_redundant_indices = setdiff(non_redundant_indices, j)
            else
                # the constraint is not redundant
                i = i+1
            end
        else
            error("LP is not optimal; the status of the LP is $(lp.status)")
        end
    end

    deleteat!(constraints, setdiff(1:m, non_redundant_indices))
    return true
end

"""
    remove_redundant_constraints(
        constraints::AbstractVector{<:LinearConstraint{N}};
        backend=default_lp_solver(N)) where {N<:Real}

Remove the redundant constraints of a given list of linear constraints.

### Input

- `constraints` -- list of constraints
- `backend`     -- (optional, default: `default_lp_solver(N)`) the backend used
                   to solve the linear program
### Output

The list of constraints with the redundant ones removed, or an empty set if the
constraints are infeasible.

### Algorithm

See `remove_redundant_constraints!(::AbstractVector{<:LinearConstraint})` for
details.
"""
function remove_redundant_constraints(
        constraints::AbstractVector{<:LinearConstraint{N}};
        backend=default_lp_solver(N)) where {N<:Real}
    constraints_copy = copy(constraints)
    if remove_redundant_constraints!(constraints_copy, backend=backend)
        return constraints_copy
    else  # the constraints are infeasible
        return EmptySet{N}()
    end
end

"""
    linear_map(M::AbstractMatrix{N},
               P::AbstractPolyhedron{N};
               [algorithm]::Union{String, Nothing}=nothing,
               [check_invertibility]::Bool=true,
               [cond_tol]::Number=DEFAULT_COND_TOL,
               [inverse]::Union{AbstractMatrix{N}, Nothing}=nothing
              ) where {N<:Real}

Concrete linear map of a polyhedral set.

### Input

- `M`         -- matrix
- `P`         -- polyhedral set
- `algorithm` -- (optional; default: `nothing`, see the Notes section below)
                 algorithm to be used; possible choices are:
  - `"vrep"`     -- apply the linear map to each vertex of `P` (note that this
                    only works for *polytopes*)
  - `"inverse"`  -- compute the matrix inverse and apply it to each constraint
                    of `P`
  - `"division"` -- divide each constraint of `P` by `M` from the left
- `check_invertibility` -- (optional, deault: `true`) check if the linear map is
                           invertible, in which case this function uses the
                           matrix inverse; if this flag is set to `false`, we
                           assume that the matrix is invertible; otherwise, if
                           the invertibility check fails, we fall back to the
                           `"vrep"` algorithm; this option is ignored if the
                           `"vrep"` algorithm is used
- `cond_tol`  -- (optional; default: `DEFAULT_COND_TOL`) tolerance of matrix
                 condition (used to check whether the matrix is invertible)
- `inverse`   -- (optional; default: `nothing`) matrix inverse (if known)

### Output

The type of the result is "as close as possible" to the the type of `P`.
Let `(m, n)` be the size of `M`, where `m ≠ n` is allowed for rectangular maps.

To fix the type of the output to something different than the default value,
consider post-processing the result of this function with a call to a suitable
`convert` method.

In particular, the output depends on the type of `P`, on `m`, and the algorithm
that was used:

- If the vertex-based approach was used:

    - If `P` is a `VPolygon` and `m = 2` then the output is a `VPolygon`.
    - If `P` is a `VPolytope` then the output is a `VPolytope`.
    - Otherwise, the output is an `Interval` if `m = 1`, a `VPolygon` if `m = 2`
      and a `VPolytope` in other cases.

- If the invertibility criterion was used:

    - The types of `HalfSpace`, `Hyperplane`, `Line` and `AbstractHPolygon` are
      preserved.
    - If `P` is an `AbstractPolytope`, then the output is an `Interval` if `m = 1`,
      an `HPolygon` if `m = 2` and an `HPolytope` in other cases.
    - Otherwise, the output is an `HPolyhedron`.

### Notes

If `algorithm` is `nothing` (the default), we determine the algorithm as
follows.
If `M` is sparse or non-square, and has full row rank (which we check), we use
`"division"`.
If `M` is dense and square and invertible (either assumed or checked; see option
`check_invertibility`), we use `"inverse"`.
Otherwise, we use `"vrep"`.

### Algorithm

This function implements two algorithms for the linear map:

- If the matrix ``M`` is invertible (which we check via a sufficient condition),
  then ``y = M x`` implies ``x = \\text{inv}(M) y`` and we transform the
  constraint system ``A x ≤ b`` to ``A \\text{inv}(M) y ≤ b``.
- Otherwise, we transform the polyhedron to vertex representation and apply the
  map to each vertex, returning a polyhedron in vertex representation.

Note that the vertex representation (second approach) is only available if the
polyhedron is bounded, which we check.

If the matrix is known to be invertible, the the option `check_invertibility`
can be used to skip the invertibility test.
Note that we only check for invertibility if the `algorithm` is either
unspecified or specified as `"inverse"`.
If the matrix inverse is even known, it can be specified with the option
`inverse`, in which case we ignore the other options and also the original
matrix `M`.

The algorithms `"division"` and `"inverse"` give control about whether the full
matrix inverse is computed or only the left division on the normal vectors is
used.
Note that this helps as a workaround when `M` is sparse (since the `inv`
function is not available for sparse matrices) or rectangular.
For sparse and invertible matrices, either use the algorithm `"division"` or
convert `M` to a dense matrix (as in `linear_map(Matrix(M), P)`).

Internally, this function operates on the level of the `AbstractPolyhedron`
interface, but the actual algorithm uses dispatch on the concrete type of `P`,
depending on the algorithm that is used:

- `_linear_map_vrep(M, P)` if the vertex approach is used
- `_linear_map_hrep(M, P, use_inv)` if the invertibility criterion is used,
  where `use_inv` is determined by the algorithm

New subtypes of the interface should define their own `_linear_map_vrep`
(resp. `_linear_map_hrep`) for special handling of the linear map; otherwise
the fallback implementation for `AbstractPolyhedron` is used.
"""
function linear_map(M::AbstractMatrix{N},
                    P::AbstractPolyhedron{N};
                    algorithm::Union{String, Nothing}=nothing,
                    check_invertibility::Bool=true,
                    cond_tol::Number=DEFAULT_COND_TOL,
                    inverse::Union{AbstractMatrix{N}, Nothing}=nothing
                   ) where {N<:Real}
    # if `inverse` is specified, we ignore other inputs and do not check them
    if inverse != nothing
        return _linear_map_hrep(M, P, true; inverse=inverse)
    end

    @assert dim(P) == size(M, 2) "a linear map of size $(size(M)) cannot be " *
        "applied to a set of dimension $(dim(P))"

    if algorithm == nothing
        if issparse(M) || !issquare(M)
            if hasfullrowrank(M)
                algorithm = "division"
            else
                algorithm = "vrep"
            end
        elseif !check_invertibility || isinvertible(M; cond_tol=cond_tol)
            algorithm = "inverse"
        else
            algorithm = "vrep"
        end
    elseif algorithm == "inverse"
        # check invertibility
        if check_invertibility && !isinvertible(M; cond_tol=cond_tol)
            throw(ArgumentError("algorithm \"inverse\" requires an " *
                                "invertible matrix"))
        end
    end

    if algorithm == "vrep"
        return _linear_map_vrep(M, P)
    else
        if algorithm == "inverse"
            use_inv = true
        elseif algorithm == "division"
            use_inv = false
        else
            throw(ArgumentError("got unknown algorithm \"$algorithm\"; " *
                "available choices: \"vrep\", \"inverse\", \"division\""))
        end
        return _linear_map_hrep(M, P, use_inv)
    end
end

# handle different numeric types
function linear_map(M::AbstractMatrix{NM},
                    P::AbstractPolyhedron{NP};
                    kwargs...) where {NM<:Real, NP<:Real}
    N = promote_type(NM, NP)
    if N != NP
        error("conversion between numeric types of polyhedra not implemented " *
            "yet (see #1181)")
    else
        return linear_map(N.(M), P; kwargs...)
    end
end

function _linear_map_vrep(M::AbstractMatrix{N}, P::AbstractPolyhedron{N}) where {N<:Real}
    if !isbounded(P)
        throw(ArgumentError("the linear map in vertex representation for an " *
            "unbounded set is not defined"))
    end
    require(:Polyhedra; fun_name="linear_map",
            explanation="of a $(typeof(P)) by a non-invertible matrix")
    # since P is bounded, we pass an HPolytope and then convert it to vertex representation
    P = tovrep(HPolytope(constraints_list(P), check_boundedness=false))
    return _linear_map_vrep(M, P)
end

function _linear_map_hrep(M::AbstractMatrix{N}, P::AbstractPolyhedron{N},
                          use_inv::Bool;
                          inverse::Union{Nothing, AbstractMatrix{N}}=nothing
                         ) where {N<:Real}
    constraints = _linear_map_hrep_helper(M, P, use_inv, inverse=inverse)
    return HPolyhedron(constraints)
end

function _linear_map_hrep_helper(M::AbstractMatrix{N}, P::AbstractPolyhedron{N},
                                 use_inv::Bool;
                                 inverse::Union{Nothing, AbstractMatrix{N}}=nothing
                                ) where {N<:Real}
    constraints_P = constraints_list(P)
    constraints_MP = similar(constraints_P)
    if use_inv || inverse != nothing
        if inverse == nothing
            inverse = inv(M)
        end
        @inbounds for (i, c) in enumerate(constraints_P)
            constraints_MP[i] =
                LinearConstraint(vec(_At_mul_B(c.a, inverse)), c.b)
        end
    else
        # take left division for each constraint c, transpose(M) \ c.a
        @inbounds for (i, c) in enumerate(constraints_P)
            constraints_MP[i] = LinearConstraint(_At_ldiv_B(M, c.a), c.b)
        end
    end
    return constraints_MP
end

"""
    plot_recipe(P::AbstractPolyhedron{N}, [ε]::N=zero(N)) where {N<:Real}

Convert a (bounded) polyhedron to a pair `(x, y)` of points for plotting.

### Input

- `P` -- bounded polyhedron
- `ε` -- (optional, default: `0`) ignored, used for dispatch

### Output

A pair `(x, y)` of points that can be plotted.

### Algorithm

We first assert that `P` is bounded (i.e., that `P` is a polytope).

One-dimensional polytopes are converted to an `Interval`.
Three-dimensional or higher-dimensional polytopes are not supported.

For two-dimensional polytopes (i.e., polygons) we compute their set of vertices
using `vertices_list` and then plot the convex hull of these vertices.
"""
function plot_recipe(P::AbstractPolyhedron{N}, ε::N=zero(N)) where {N<:Real}
    @assert dim(P) <= 2 "cannot plot a $(dim(P))-dimensional $(typeof(P))"
    @assert isbounded(P) "cannot plot an unbounded $(typeof(P))"

    if dim(P) == 1
        return plot_recipe(convert(Interval, P), ε)
    else
        vlist = transpose(hcat(convex_hull(vertices_list(P))...))
        if isempty(vlist)
            @warn "received a polyhedron with no vertices during plotting"
            return plot_recipe(EmptySet{N}(), ε)
        end
        x, y = vlist[:, 1], vlist[:, 2]

        if length(x) > 1
            # add first vertex to "close" the polygon
            push!(x, x[1])
            push!(y, y[1])
        end

        return x, y
    end
end

"""
    chebyshev_center(P::AbstractPolyhedron{N};
                     [get_radius]::Bool=false,
                     [backend]=default_polyhedra_backend(P, N),
                     [solver]=JuMP.with_optimizer(GLPK.Optimizer)
                     ) where {N<:AbstractFloat}

Compute the [Chebyshev center](https://en.wikipedia.org/wiki/Chebyshev_center)
of a polytope.

### Input

- `P`          -- polytope
- `get_radius` -- (optional; default: `false`) option to additionally return the
                  radius of the largest ball enclosed by `P` around the
                  Chebyshev center
- `backend`    -- (optional; default: `default_polyhedra_backend(P, N)`) the
                  backend for polyhedral computations
- `solver`     -- (optional; default: `JuMP.with_optimizer(GLPK.Optimizer)`) the
                  LP solver passed to `Polyhedra`

### Output

If `get_radius` is `false`, the result is the Chebyshev center of `P`.
If `get_radius` is `true`, the result is the pair `(c, r)` where `c` is the
Chebyshev center of `P` and `r` is the radius of the largest ball with center
`c` enclosed by `P`.

### Notes

The Chebyshev center is the center of a largest Euclidean ball enclosed by `P`.
In general, the center of such a ball is not unique (but the radius is).
"""
function chebyshev_center(P::AbstractPolyhedron{N};
                          get_radius::Bool=false,
                          backend=default_polyhedra_backend(P, N),
                          solver=JuMP.with_optimizer(GLPK.Optimizer)
                         ) where {N<:AbstractFloat}
    require(:Polyhedra; fun_name="chebyshev_center")
    # convert to HPolyhedron to ensure `polyhedron` is applicable (see #1505)
    Q = polyhedron(convert(HPolyhedron, P); backend=backend)
    c, r = Polyhedra.chebyshevcenter(Q, solver)

    if get_radius
        return c, r
    end
    return c
end
