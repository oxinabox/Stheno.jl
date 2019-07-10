import Base: rand, length
import Distributions: logpdf, ContinuousMultivariateDistribution

export mean, std, cov, marginals, rand, logpdf, elbo



"""
    FiniteGP{Tf, Tx}

The finite-dimensional projection of the GP `f` at `x`.
"""
struct FiniteGP{Tf<:GP, Tx<:AV, TΣy} <: ContinuousMultivariateDistribution
    f::Tf
    x::Tx 
    Σy::TΣy
    function FiniteGP(f::Tf, x::Tx, Σy::TΣy) where {Tf<:GP, Tx<:AV, TΣy}
        @assert length(x) == size(Σy, 1)
        return new{Tf, Tx, TΣy}(f, x, Σy)
    end
end
FiniteGP(f::GP, x::AV, σ²::AV{<:Real}) = FiniteGP(f, x, Diagonal(σ²))
FiniteGP(f::GP, x::AV, σ²::Real) = FiniteGP(f, x, fill(σ², length(x)))
FiniteGP(f::GP, x::AV) = FiniteGP(f, x, 0)

length(f::FiniteGP) = length(f.x)



"""
    mean(f::FiniteGP)

The mean vector of `f`.
"""
mean(f::FiniteGP) = ew(mean(f.f), f.x)



"""
    cov(f::FiniteGP)

The covariance matrix of `f`.
"""
cov(f::FiniteGP) = pairwise(kernel(f.f), f.x) + f.Σy



"""
    cov(f::FiniteGP, g::FiniteGP)

The cross-covariance between `f` and `g`.
"""
cov(f::FiniteGP, g::FiniteGP) = pairwise(kernel(f.f, g.f), f.x, g.x)



"""
    marginals(f::FiniteGP)

Sugar, returns a vector of Normal distributions representing the marginals of `f`.
"""
marginals(f::FiniteGP) = Normal.(mean(f), sqrt.(ew(kernel(f.f), f.x) .+ diag(f.Σy)))



"""
    rand(rng::AbstractRNG, f::FiniteGP, N::Int=1)

Obtain `N` independent samples from the GP `f` using `rng`.
"""
rand(rng::AbstractRNG, f::FiniteGP, N::Int) = _rand(rng, f, N)
rand(f::FiniteGP, N::Int) = rand(Random.GLOBAL_RNG, f, N)

rand(rng::AbstractRNG, f::FiniteGP) = vec(rand(rng, f, 1))
rand(f::FiniteGP) = rand(Random.GLOBAL_RNG, f)

function _rand(rng::AbstractRNG, f::FiniteGP, N::Int)
    μ, C = mean(f), cholesky(Symmetric(cov(f)))
    return μ .+ C.U' * randn(rng, length(μ), N)
end

_rand(rng::AbstractRNG, f::FiniteGP) = vec(_rand(rng, f, 1))



"""
    logpdf(f::FiniteGP, y::AbstractVector{<:Real})

The log probability density of `y` under `f`.
"""
logpdf(f::FiniteGP, y::AbstractVector{<:Real}) = _logpdf(f, y)

function _logpdf(f::FiniteGP, y::AbstractVector{<:Real})
    μ, C = mean(f), cholesky(Symmetric(cov(f)))
    return -(length(y) * log(2π) + logdet(C) + Xt_invA_X(C, y - μ)) / 2
end



"""
    elbo(f::FiniteGP, y::AbstractVector{<:Real}, u::FiniteGP)

The saturated Titsias-ELBO.
"""
function elbo(f::FiniteGP, y::AV{<:Real}, u::FiniteGP)
    consistency_check(f, y, u)
    chol_Σy = cholesky(f.Σy)

    A = cholesky(Symmetric(cov(u))).U' \ (chol_Σy.U' \ cov(f, u))'
    Λ_ε = cholesky(Symmetric(A * A' + I))
    δ = chol_Σy.U' \ (y - mean(f))

    return -(length(y) * log(2π) + logdet(chol_Σy) + logdet(Λ_ε) +
        sum(abs2, δ) - sum(abs2, Λ_ε.U' \ (A * δ)) +
        tr_Cf_invΣy(f, f.Σy, chol_Σy) - sum(abs2, A)) / 2
end

function consistency_check(f, y, u)
    @assert length(f) == length(y)
end
Zygote.@nograd consistency_check

import Base: \ 
\(A::AbstractMatrix, B::Diagonal) = A \ Matrix(B)

\(A::Union{LowerTriangular, UpperTriangular}, B::Diagonal) = A \ Matrix(B)
\(A::Adjoint{<:Any, <:Union{LowerTriangular, UpperTriangular}}, B::Diagonal) = A \ Matrix(B)


# Compute tr(Cf / Σy) efficiently for different types of Σy. For dense Σy you obviously need
# to compute the entirety of Cf, which is bad, but for particular structured Σy one requires
# only a subset of the elements. Σy isa UniformScaling is version usually considered.
function tr_Cf_invΣy(f::FiniteGP, Σy::UniformScaling, chol_Σy::Cholesky)
    return sum(ew(kernel(f.f), f.x)) / Σy.λ
end
function tr_Cf_invΣy(f::FiniteGP, Σy::Diagonal, chol_Σy::Cholesky)
    return sum(ew(kernel(f.f), f.x) ./ diag(Σy))
end
function tr_Cf_invΣy(f::FiniteGP, Σy::Matrix, chol_Σy::Cholesky)
    return tr(chol_Σy \ pw(kernel(f.f), f.x))
end
function tr_Cf_invΣy(f::FiniteGP, Σy::BlockDiagonal, chol_Σy::Cholesky)
    C = cholesky(Symmetric(_get_kernel_block_diag(f, cumulsizes(Σy, 1))))
    return tr_At_A(chol_Σy.U' \ C.U')
end

function _get_kernel_block_diag(f::FiniteGP, cs)
    k = kernel(f.f)
    ids = map(n->cs[n]:cs[n+1]-1, 1:length(cs)-1)
    xs = map(id->f.x[id], ids)
    Σs = map(x->pw(k, x), xs)
    return block_diagonal(Σs)
end

function _get_kernel_block_diag(f::FiniteGP{<:GP{<:BlockMean, <:BlockKernel}, <:BlockData}, cs)
    k = kernel(f.f)
    ids = map(n->cs[n]:cs[n+1]-1, 1:length(cs)-1)
    @assert _test_block_consistency(ids, f)
    xs = blocks(f.x)
    Σs = map(n->pw(k.ks[n], xs[n]), 1:length(xs))
    return block_diagonal(Σs)
end

_test_block_consistency(ids, f) = length.(ids) == length.(blocks(f.x))
Zygote.@nograd _test_block_consistency

# """
#     elbo(f::FiniteGP, y::AV{<:Real}, u::FiniteGP, mε::AV{<:Real}, Λε::AM{<:Real})

# The unsaturated Titsias-ELBO.
# """
# function elbo(f::FiniteGP, y::AV{<:Real}, u::FiniteGP, mε::AV{<:Real}, Λε::AM{<:Real})
#     @assert length(u.x) == length(mε)
#     @assert size(Λε) == (length(mε), length(mε))
#     # do stuff.
# end

import Base: |, merge
export ←, |



"""
    Observation

Represents fixing a paricular (finite) GP to have a particular (vector) value.
"""
struct Observation{Tf<:FiniteGP, Ty<:AbstractVector{<:Real}}
    f::Tf
    y::Ty
end

const Obs = Observation
export Obs

←(f, y) = Observation(f, y)
get_f(c::Observation) = c.f
get_y(c::Observation) = c.y
