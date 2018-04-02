import Base: +, *, ==
export KernelType, Kernel, EQ, RQ, Linear, Poly, Noise, Wiener, WienerVelocity, Exponential,
    Constant

"""
Determines whether a kernel is stationary or not and enables dispatch on this.
"""
abstract type KernelType end

""" Indicates that a `Kernel` is non-stationary. """
abstract type NonStationary <: KernelType end

""" Indicates that a `Kernel` is stationary. """
abstract type Stationary <: KernelType end

"""
    Kernel{T<:KernelType}

Supertype for all kernels; `T` indicates whether is `Stationary` or `NonStationary`.
"""
abstract type Kernel{T<:KernelType} end

isfinite(::Kernel) = false

"""
    Zero <: Kernel{Stationary}

A rank 1 kernel that always returns zero.
"""
struct Zero <: Kernel{Stationary} end
(::Zero)(x::T, x′::T) where T = zero(T)

"""
    Constant{T<:Real} <: Kernel{Stationary}

A rank 1 constant `Kernel`. Useful for consistency when creating composite Kernels,
but (almost certainly) shouldn't be used as a base `Kernel`.
"""
struct Constant{T<:Real} <: Kernel{Stationary}
    value::T
end
(k::Constant)(::Any, ::Any) = k.value
==(a::Constant, b::Constant) = a.value == b.value

"""
    EQ <: Kernel{Stationary}

The standardised Exponentiated Quadratic kernel with no free parameters.
"""
struct EQ <: Kernel{Stationary} end
@inline (::EQ)(x::Real, y::Real) = exp(-0.5 * abs2(x - y))
==(::EQ, ::EQ) = true

"""
    RQ{T<:Real} <: Kernel{Stationary}

The standardised Rational Quadratic. `RQ(α)` creates an `RQ` `Kernel{Stationary}` whose
kurtosis is `α`.
"""
struct RQ{T<:Real} <: Kernel{Stationary}
    α::T
end
@inline (k::RQ)(x::Real, y::Real) = (1 + 0.5 * abs2(x - y) / k.α)^(-k.α)
==(a::RQ, b::RQ) = a.α == b.α

"""
    Linear{T<:Real} <: Kernel{NonStationary}

Standardised linear kernel. `Linear(c)` creates a `Linear` `Kernel{NonStationary}` whose
intercept is `c`.
"""
struct Linear{T<:Real} <: Kernel{NonStationary}
    c::T
end
@inline (k::Linear)(x, y) = dot(x - k.c, y - k.c)
@inline (k::Linear)(x::Tuple, y::Tuple) = sum(map((x, y)->(x - k.c) * (y - k.c), x, y))
==(a::Linear, b::Linear) = a.c == b.c

"""
    Poly{Tσ<:Real} <: Kernel{NonStationary}

Standardised Polynomial kernel. `Poly(p, σ)` creates a `Poly` `Kernel{NonStationary}`.
"""
struct Poly{Tσ<:Real} <: Kernel{NonStationary}
    p::Int
    σ::Tσ
end
@inline (k::Poly)(x::Real, x′::Real) = (x * x′ + k.σ)^k.p

"""
    Noise{T<:Real} <: Kernel{Stationary}

A standardised stationary white-noise kernel.
"""
struct Noise <: Kernel{Stationary} end
@inline (::Noise)(x::Real, x′::Real) = x == x′ ? 1.0 : 0.0
==(::Noise, ::Noise) = true

"""
    Wiener <: Kernel{NonStationary}

The standardised stationary Wiener-process kernel.
"""
struct Wiener <: Kernel{NonStationary} end
@inline (::Wiener)(x::Real, x′::Real) = min(x, x′)
==(::Wiener, ::Wiener) = true

"""
    WienerVelocity <: Kernel{NonStationary}

The standardised WienerVelocity kernel.
"""
struct WienerVelocity <: Kernel{NonStationary} end
@inline (::WienerVelocity)(x::Real, x′::Real) =
    min(x, x′)^3 / 3 + abs(x - x′) * min(x, x′)^2 / 2
==(::WienerVelocity, ::WienerVelocity) = true

"""
    Exponential <: Kernel{Stationary}

The standardised Exponential kernel.
"""
struct Exponential <: Kernel{Stationary} end
@inline (::Exponential)(x::Real, x′::Real) = exp(-abs(x - x′))
==(::Exponential, ::Exponential) = true
