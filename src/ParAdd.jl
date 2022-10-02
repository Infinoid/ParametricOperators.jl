export ParAdd

struct ParAdd{D,R,L,P,F} <: ParOperator{D,R,L,P,Internal}
    ops::F
    m::Int64
    n::Int64
    ranges::Vector{UnitRange{Int64}}
    slots::Set{Int64}
    id::ID
    function ParAdd(ops::ParOperator...)
        @assert allequal(map(Domain, ops))
        @assert allequal(map(Range, ops))
        @assert allequal(map(DDT, ops))
        @assert allequal(map(RDT, ops))
        D_out = DDT(ops[1])
        R_out = RDT(ops[1])
        L_out = foldl((l1, l2) -> promote_linearity(l1, l2), map(linearity, ops); init = Linear)
        P_out = foldl((p1, p2) -> promote_parametricity(p1, p2), map(parametricity, ops); init = NonParametric)
        offsets = [0, cumsum(map(nparams, ops[1:end-1]))...]
        starts = offsets .+ 1
        stops = [o+np for (o, np) in zip(offsets, map(nparams, ops))]
        ranges = [start:stop for (start, stop) in zip(starts, stops)]
        slots = Set(map(tup -> tup[1], filter(tup -> length(tup[2]) > 0, collect(enumerate(ranges)))))
        return new{D_out,R_out,L_out,P_out,typeof(ops)}(ops, Range(ops[1]), Domain(ops[1]), ranges, slots, uuid4(GLOBAL_RNG))
    end
end

+(ops::ParOperator...) = ParAdd(ops...)

Domain(A::ParAdd) = A.n
Range(A::ParAdd) = A.m
children(A::ParAdd) = A.ops
id(A::ParAdd) = A.id
adjoint(A::ParAdd{D,R,Linear,P,F}) where {D,R,P,F} = ParAdd(map(adjoint, A.ops)...)

(A::ParAdd{D,R,L,Parametric,F})(θ::AbstractVector{<:Number}) where {D,R,L,F} =
    ParAdd([i ∈ A.slots ? op(θ[range]) : op for (i, (op, range)) in enumerate(zip(A.ops, A.ranges))]...)

(A::ParAdd{D,R,L,P,F})(x::X) where {D,R,L,P<:Applicable,F,X<:AbstractVector{D}} = +(map(op -> op(x), A.ops)...)