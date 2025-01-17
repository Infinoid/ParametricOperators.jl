export ParOperator, ParLinearOperator, ParNonLinearOperator
export DDT, RDT, Domain, Range, linearity, parametricity, ast_location
export children, nparams, init, from_children

# ==== Type Definitions ====

"""
Typeflag for whether a given operator is linear.
"""
abstract type Linearity end
struct Linear <: Linearity end
struct NonLinear <: Linearity end

"""
Linearity promotion rules.
"""
promote_linearity(::Type{Linear}, ::Type{Linear}) = Linear
promote_linearity(::Type{<:Linearity}, ::Type{<:Linearity}) = NonLinear

"""
Typeflag for whether a given operator is parametric, nonparametric, or parameterized
with some given parameters.

Note: A distinction is made for parametric vs. parameterized to allow for proper
method dispatch.
"""
abstract type Parametricity end
struct Parametric <: Parametricity end
struct NonParametric <: Parametricity end
struct Parameterized <: Parametricity end

"""
Applicable types can act on vectors.
"""
const Applicable = Union{NonParametric, Parameterized}

"""
HasParams types have parameter slots or associated parameters.
"""
const HasParams = Union{Parametric, Parameterized}

"""
Parametricity promotion rules.
"""
promote_parametricity(::Type{NonParametric}, ::Type{NonParametric}) = NonParametric
promote_parametricity(::Type{NonParametric}, ::Type{Parameterized}) = Parameterized
promote_parametricity(::Type{Parameterized}, ::Type{NonParametric}) = Parameterized
promote_parametricity(::Type{Parameterized}, ::Type{Parameterized}) = Parameterized
promote_parametricity(::Type{<:Parametricity}, ::Type{<:Parametricity}) = Parametric

"""
Typeflag for whether a given operator is an external or internal node in the AST
generated by combining operators together.
"""
abstract type ASTLocation end
struct Internal <: ASTLocation end
struct External <: ASTLocation end

"""
Base operator type.
"""
abstract type ParOperator{D,R,L<:Linearity,P<:Parametricity,T<:ASTLocation} end

"""
Linear operator type (defined for convenience).
"""
const ParLinearOperator{D,R,P,T} = ParOperator{D,R,Linear,P,T}

"""
Nonlinear operator type (defined for convenience).
"""
const ParNonLinearOperator{D,R,P,T} = ParOperator{D,R,NonLinear,P,T}

"""
Parametric operator type (defined for convenience).
"""
const ParParametricOperator{D,R,L,T} = ParOperator{D,R,L,Parametric,T}

# ==== Trait Definitions ====

"""
Domain datatype of the given operator.
"""
DDT(::ParOperator{D,R,L,P,T}) where {D,R,L,P,T} = D

"""
Range datatype of the given operator.
"""
RDT(::ParOperator{D,R,L,P,T}) where {D,R,L,P,T} = R

"""
Linearity of the given operator.
"""
linearity(::ParOperator{D,R,L,P,T}) where {D,R,L,P,T} = L

"""
Parametricity of the given operator.
"""
parametricity(::ParOperator{D,R,L,P,T}) where {D,R,L,P,T} = P

"""
AST location of the given operator.
"""
ast_location(::ParOperator{D,R,L,P,T}) where {D,R,L,P,T} = T

"""
Domain of the given operator. In parallel computation, corresponds to the local
domain size.
"""
Domain(::ParOperator) = throw(ParException("Unimplemented"))

"""
Range of the given operator. In parallel computation, corresponds to the local
range size.
"""
Range(::ParOperator) = throw(ParException("Unimplemented"))

"""
Children of the given operator. For external nodes, this is an empty list.
"""
children(::ParOperator{D,R,L,P,External}) where {D,R,L,P} = []
children(::ParOperator{D,R,L,P,Internal}) where {D,R,L,P} = throw(ParException("Unimplemented"))

"""
Number of non-const parameters of the given operator.
"""
nparams(::ParOperator{D,R,L,<:Applicable,T}) where {D,R,L,T} = 0
nparams(A::ParOperator{D,R,L,Parametric,Internal}) where {D,R,L} = sum(map(nparams, children(A)))

"""
Initialize the given operator
"""
init(::ParOperator{D,R,L,<:Applicable,T}) where {D,R,L,T} = []
init(A::ParOperator{D,R,L,Parametric,Internal}) where {D,R,L} = collect(Iterators.flatten(map(init, children(A))))

"""
Rebuild the given operator from a list of children.
"""
from_children(A::ParOperator{D,R,L,P,External}, _) where {D,R,L,P} = A
from_children(::ParOperator{D,R,L,P,Internal}, _) where {D,R,L,P} = throw(ParException("Unimplemented"))

"""
Parameterize the given operator
"""
function (A::ParOperator{D,R,L,Parametric,Internal})(params) where {D,R,L}
    param_ranges = cumranges([nparams(c) for c in children(A)])
    cs_out = [parametricity(c) == Parametric ? c(params[r]) : c for (c, r) in zip(children(A), param_ranges)]
    return from_children(A, cs_out)
end

"""
Get the parameters of a given operator
"""
params(::ParOperator{D,R,L,NonParametric,T}) where {D,R,L,T} = []
params(::ParOperator{D,R,L,Parametric,External}) where {D,R,L} = []
params(A::ParOperator{D,R,L,<:Union{Parametric,Parameterized},Internal}) where {D,R,L} =
    collect(Iterators.flatten(map(params, children(A))))

# ==== Functionality Definitions ====

"""
Apply the given operator on a vector.
"""
(A::ParOperator{D,R,L,<:Applicable,T})(::X) where {D,R,L,T,X<:AbstractVector{D}} = throw(ParException("Unimplemented"))

"""
Apply the given operator to a matrix. By default, apply to each of the columns.
"""
(A::ParOperator{D,R,L,<:Applicable,T})(x::X) where {D,R,L,T,X<:AbstractMatrix{D}} = mapreduce(col -> A(col), hcat, eachcol(x))

"""
Apply a nonlinear operator on a vector.
"""
(A::ParNonLinearOperator{D,R,Parametric,T})(x::X, θ) where {D,R,T,X<:AbstractVector{D}} = A(θ)(x)
(A::ParNonLinearOperator{D,R,Parametric,T})(x::X, θ) where {D,R,T,X<:AbstractMatrix{D}} = A(θ)(x)

"""
Apply a linear operator to a vector or matrix through multiplication.
"""
*(A::ParOperator{D,R,L,<:Applicable,T}, x::X) where {D,R,L,T,X<:AbstractVector{D}} = A(x)
*(A::ParOperator{D,R,L,<:Applicable,T}, x::X) where {D,R,L,T,X<:AbstractMatrix{D}} = A(x)

"""
Apply a matrix to a linear operator. By default, use rules of the adjoint.
"""
*(x::X, A::ParLinearOperator{D,R,<:Applicable,T}) where {D,R,T,X<:AbstractMatrix{R}} = (A'*x')'
