# Filter types and conversions

abstract type FilterCoefficients end

realtype(x::DataType) = x
realtype(::Type{Complex{T}}) where {T} = T
complextype(T::DataType) = Complex{T}
complextype(::Type{Complex{T}}) where {T} = Complex{T}

#
# Zero-pole gain form
#

struct ZeroPoleGain{Z<:Number,P<:Number,K<:Number} <: FilterCoefficients
    z::Vector{Z}
    p::Vector{P}
    k::K
end

Base.promote_rule(::Type{ZeroPoleGain{Z1,P1,K1}}, ::Type{ZeroPoleGain{Z2,P2,K2}}) where {Z1,P1,K1,Z2,P2,K2} =
    ZeroPoleGain{promote_type(Z1,Z2),promote_type(P1,P2),promote_type(K1,K2)}
Base.convert(::Type{ZeroPoleGain{Z,P,K}}, f::ZeroPoleGain{Z,P,K}) where {Z,P,K} = f
Base.convert(::Type{ZeroPoleGain{Z,P,K}}, f::ZeroPoleGain) where {Z,P,K} =
    ZeroPoleGain{Z,P,K}(f.z, f.p, f.k)

*(f::ZeroPoleGain, g::Number) = ZeroPoleGain(f.z, f.p, f.k*g)
*(g::Number, f::ZeroPoleGain) = ZeroPoleGain(f.z, f.p, f.k*g)
*(f1::ZeroPoleGain, f2::ZeroPoleGain) =
    ZeroPoleGain([f1.z; f2.z], [f1.p; f2.p], f1.k*f2.k)
*(f1::ZeroPoleGain, fs::ZeroPoleGain...) =
    ZeroPoleGain(vcat(f1.z, [f.z for f in fs]...), vcat(f1.p, [f.p for f in fs]...), f1.k*prod([f.k for f in fs]))

#
# Transfer function form
#

struct PolynomialRatio{T<:Number} <: FilterCoefficients
    b::Poly{T}
    a::Poly{T}

    PolynomialRatio{Ti}(b::Poly, a::Poly) where {Ti<:Number} =
        new{Ti}(convert(Poly{Ti}, b/a[end]), convert(Poly{Ti}, a/a[end]))
end
PolynomialRatio(b::Poly{T}, a::Poly{T}) where {T<:Number} = PolynomialRatio{T}(b, a)

# The DSP convention is highest power first. The Polynomials.jl
# convention is lowest power first.
function PolynomialRatio(b::Union{T,Vector{T}}, a::Union{S,Vector{S}}) where {T<:Number,S<:Number}
    if findfirst(b) == 0 || findfirst(a) == 0
        throw(ArgumentError("filter must have non-zero numerator and denominator"))
    end
    PolynomialRatio{promote_type(T,S)}(Poly(b[end:-1:findfirst(b)]), Poly(a[end:-1:findfirst(a)]))
end

Base.promote_rule(::Type{PolynomialRatio{T}}, ::Type{PolynomialRatio{S}}) where {T,S} = PolynomialRatio{promote_type(T,S)}
Base.convert(::Type{PolynomialRatio{T}}, f::PolynomialRatio{T}) where {T} = f
Base.convert(::Type{PolynomialRatio{T}}, f::PolynomialRatio) where {T} = PolynomialRatio{T}(f.b, f.a)

function Base.convert(::Type{PolynomialRatio{T}}, f::ZeroPoleGain) where T<:Real
    b = f.k*poly(f.z)
    a = poly(f.p)
    PolynomialRatio{T}(Poly(real(b.a)), Poly(real(a.a)))
end
Base.convert(::Type{PolynomialRatio}, f::ZeroPoleGain{Z,P,K}) where {Z,P,K} =
    convert(PolynomialRatio{promote_type(realtype(Z),realtype(P),K)}, f)

function Base.convert(::Type{ZeroPoleGain{Z,P,K}}, f::PolynomialRatio) where {Z,P,K}
    k = real(f.b[end])
    ZeroPoleGain{Z,P,K}(roots(f.b / k), roots(f.a), k)
end
Base.convert(::Type{ZeroPoleGain}, f::PolynomialRatio{T}) where {T} =
    convert(ZeroPoleGain{complextype(T),complextype(T),T}, f)

*(f::PolynomialRatio, g::Number) = PolynomialRatio(g*f.b, f.a)
*(g::Number, f::PolynomialRatio) = PolynomialRatio(g*f.b, f.a)
*(f1::PolynomialRatio, f2::PolynomialRatio) =
    PolynomialRatio(f1.b*f2.b, f1.a*f2.a)
*(f1::PolynomialRatio, fs::PolynomialRatio...) =
    PolynomialRatio(f1.b*prod([f.b for f in fs]), f1.a*prod([f.a for f in fs]))

coefb(f::PolynomialRatio) = reverse(f.b.a)
coefa(f::PolynomialRatio) = reverse(f.a.a)

#
# Biquad filter in transfer function form
# A separate immutable to improve efficiency of filtering using SecondOrderSections
#

struct Biquad{T<:Number} <: FilterCoefficients
    b0::T
    b1::T
    b2::T
    a1::T
    a2::T
end
Biquad(b0::T, b1::T, b2::T, a0::T, a1::T, a2::T, g::Number=1) where {T} =
    (x = g*b0/a0; Biquad{typeof(x)}(x, g*b1/a0, g*b2/a0, a1/a0, a2/a0))

Base.promote_rule(::Type{Biquad{T}}, ::Type{Biquad{S}}) where {T,S} = Biquad{promote_type(T,S)}
Base.convert(::Type{Biquad{T}}, f::Biquad{T}) where {T} = f
Base.convert(::Type{Biquad{T}}, f::Biquad) where {T} = Biquad{T}(f.b0, f.b1, f.b2, f.a1, f.a2)

Base.convert(::Type{ZeroPoleGain{Z,P,K}}, f::Biquad) where {Z,P,K} =
    convert(ZeroPoleGain{Z,P,K}, convert(PolynomialRatio, f))
Base.convert(::Type{ZeroPoleGain}, f::Biquad) =
    convert(ZeroPoleGain, convert(PolynomialRatio, f))

function Base.convert(::Type{PolynomialRatio{T}}, f::Biquad) where T
    if f.b2 == zero(T) && f.a2 == zero(T)
        if f.b1 == zero(T) && f.a1 == zero(T)
            b = T[f.b0]
            a = T[one(T)]
        else
            b = T[f.b0, f.b1]
            a = T[one(T), f.a1]
        end
    else
        b = T[f.b0, f.b1, f.b2]
        a = T[one(T), f.a1, f.a2]
    end

    PolynomialRatio(b, a)
end
Base.convert(::Type{PolynomialRatio}, f::Biquad{T}) where {T} = convert(PolynomialRatio{T}, f)

function Base.convert(::Type{Biquad{T}}, f::PolynomialRatio) where T
    a, b = f.a, f.b
    xs = max(length(b), length(a))

    if xs == 3
        Biquad{T}(b[2], b[1], b[0], a[1], a[0])
    elseif xs == 2
        Biquad{T}(b[1], b[0], zero(T), a[0], zero(T))
    elseif xs == 1
        Biquad{T}(b[0], zero(T), zero(T), zero(T), zero(T))
    elseif xs == 0
        throw(ArgumentError("cannot convert an empty PolynomialRatio to Biquad"))
    else
        throw(ArgumentError("cannot convert a filter of length > 3 to Biquad"))
    end
end
Base.convert(::Type{Biquad}, f::PolynomialRatio{T}) where {T} = convert(Biquad{T}, f)

Base.convert(::Type{Biquad{T}}, f::ZeroPoleGain) where {T} = convert(Biquad{T}, convert(PolynomialRatio, f))
Base.convert(::Type{Biquad}, f::ZeroPoleGain) = convert(Biquad, convert(PolynomialRatio, f))

*(f::Biquad, g::Number) = Biquad(f.b0*g, f.b1*g, f.b2*g, f.a1, f.a2)
*(g::Number, f::Biquad) = Biquad(f.b0*g, f.b1*g, f.b2*g, f.a1, f.a2)

#
# Second-order sections (array of biquads)
#

struct SecondOrderSections{T,G} <: FilterCoefficients
    biquads::Vector{Biquad{T}}
    g::G
end

Base.promote_rule(::Type{SecondOrderSections{T1,G1}}, ::Type{SecondOrderSections{T2,G2}}) where {T1,G1,T2,G2} =
    SecondOrderSections{promote_type(T1,T2),promote_type(G1,G2)}
Base.convert(::Type{SecondOrderSections{T,G}}, f::SecondOrderSections{T,G}) where {T,G} = f
Base.convert(::Type{SecondOrderSections{T,G}}, f::SecondOrderSections) where {T,G} =
    SecondOrderSections{T,G}(f.biquads, f.g)

function Base.convert(::Type{ZeroPoleGain{Z,P,K}}, f::SecondOrderSections) where {Z,P,K}
    z = Z[]
    p = P[]
    k = f.g
    for biquad in f.biquads
        biquadzpk = convert(ZeroPoleGain, biquad)
        append!(z, biquadzpk.z)
        append!(p, biquadzpk.p)
        k *= biquadzpk.k
    end
    ZeroPoleGain{Z,P,K}(z, p, k)
end
Base.convert(::Type{ZeroPoleGain}, f::SecondOrderSections{T,G}) where {T,G} =
    convert(ZeroPoleGain{complextype(T),complextype(T),G}, f)

function Base.convert(::Type{Biquad{T}}, f::SecondOrderSections) where T
    if length(f.biquads) != 1
        throw(ArgumentError("only a single second order section may be converted to a biquad"))
    end
    convert(Biquad{T}, f.biquads[1]*f.g)
end
Base.convert(::Type{Biquad}, f::SecondOrderSections{T,G}) where {T,G} =
    convert(Biquad{promote_type(T,G)}, f)

Base.convert(::Type{PolynomialRatio{T}}, f::SecondOrderSections) where {T} =
    convert(PolynomialRatio{T}, convert(ZeroPoleGain, f))
Base.convert(::Type{PolynomialRatio}, f::SecondOrderSections) =
    convert(PolynomialRatio, convert(ZeroPoleGain, f))

# Group each pole in p with its closest zero in z
# Remove paired poles from p and z
function groupzp(z, p)
    unpaired = fill(true, length(z))  # whether zeros have been mapped
    n = min(length(z), length(p))
    groupedz = similar(z, n)
    for i = 1:n
        closest_zero_idx = 0
        closest_zero_val = Inf
        for j = 1:length(z)
            val = abs(z[j] - p[i])
            if val < closest_zero_val
                closest_zero_idx = j
                closest_zero_val = val
            end
        end
        groupedz[i] = splice!(z, closest_zero_idx)
    end
    ret = (groupedz, p[1:n])
    splice!(p, 1:n)
    ret
end

# Sort zeros or poles lexicographically (so that poles are adjacent to
# their conjugates). Handle repeated values. Split real and complex
# values into separate vectors. Ensure that each value has a conjugate.
function split_real_complex(x::Vector{T}) where T
    # Get counts and store in a Dict
    d = Dict{T,Int}()
    for v in x
        # needs to be in normal form since 0.0 !== -0.0
        tonormal(x) = x == 0 ? abs(x) : x
        vn = complex(tonormal(real(v)), tonormal(imag(v)))
        d[vn] = get(d, vn, 0)+1
    end

    c = T[]
    r = typeof(real(zero(T)))[]
    for k in sort!(collect(keys(d)), order=Base.Order.Lexicographic)
        if imag(k) != 0
            if !haskey(d, conj(k))
                # No match for conjugate
                return (c, r, false)
            elseif imag(k) > 0
                # Add key and its conjugate
                for n = 1:d[k]
                    push!(c, k, conj(k))
                end
            end
        else
            for n = 1:d[k]
                push!(r, k)
            end
        end
    end
    return (c, r, true)
end

# Convert a filter to second-order sections
# The returned sections are in ZPK form
function Base.convert(::Type{SecondOrderSections}, f::ZeroPoleGain{Z,P}) where {Z,P}
    z = f.z
    p = f.p
    nz = length(z)
    n = length(p)
    nz > n && throw(ArgumentError("ZeroPoleGain must not have more zeros than poles"))

    # Split real and complex poles
    (complexz, realz, matched) = split_real_complex(z)
    matched || throw(ArgumentError("complex zeros could not be matched to their conjugates"))
    (complexp, realp, matched) = split_real_complex(p)
    matched || throw(ArgumentError("complex poles could not be matched to their conjugates"))

    # Sort poles according to distance to unit circle (nearest first)
    sort!(complexp, by=x->abs(abs(x) - 1))
    sort!(realp, by=x->abs(abs(x) - 1))

    # Group complex poles with closest complex zeros
    z1, p1 = groupzp(complexz, complexp)
    # Group real poles with remaining complex zeros
    z2, p2 = groupzp(complexz, realp)
    # Group remaining complex poles with closest real zeros
    z3, p3 = groupzp(realz, complexp)
    # Group remaining real poles with closest real zeros
    z4, p4 = groupzp(realz, realp)

    # All zeros are now paired with a pole, but not all poles are
    # necessarily paired with a zero
    @assert isempty(complexz)
    @assert isempty(realz)
    groupedz = [z1; z2; z3; z4]::Vector{Z}
    groupedp = [p1; p2; p3; p4; complexp; realp]::Vector{P}
    @assert length(groupedz) == nz
    @assert length(groupedp) == n

    # Allocate memory for biquads
    T = promote_type(realtype(Z), realtype(P))
    biquads = Array{Biquad{T}}((n >> 1)+(n & 1))

    # Build second-order sections in reverse
    # First do complete pairs
    npairs = length(groupedp) >> 1
    odd = isodd(n)
    for i = 1:npairs
        pairidx = 2*(npairs-i)
        biquads[odd+i] = convert(Biquad, ZeroPoleGain(groupedz[pairidx+1:min(pairidx+2, length(groupedz))],
                                                         groupedp[pairidx+1:pairidx+2], one(T)))
    end

    if odd
        # Now do remaining pole and (maybe) zero
        biquads[1] = convert(Biquad, ZeroPoleGain(groupedz[length(groupedp):end],
                                                     [groupedp[end]], one(T)))
    end

    SecondOrderSections(biquads, f.k)
end

Base.convert(::Type{SecondOrderSections{T,G}}, f::Biquad) where {T,G} = SecondOrderSections{T,G}([f], one(G))
Base.convert(::Type{SecondOrderSections}, f::Biquad{T}) where {T} = convert(SecondOrderSections{T,Int}, f)
Base.convert(::Type{SecondOrderSections}, f::FilterCoefficients) = convert(SecondOrderSections, convert(ZeroPoleGain, f))

*(f::SecondOrderSections, g::Number) = SecondOrderSections(f.biquads, f.g*g)
*(g::Number, f::SecondOrderSections) = SecondOrderSections(f.biquads, f.g*g)
*(f1::SecondOrderSections, f2::SecondOrderSections) =
    SecondOrderSections([f1.biquads; f2.biquads], f1.g*f2.g)
*(f1::SecondOrderSections, fs::SecondOrderSections...) =
    SecondOrderSections(vcat(f1.biquads, [f.biquads for f in fs]...), f1.g*prod([f.g for f in fs]))

*(f1::Biquad, f2::Biquad) = SecondOrderSections([f1, f2], 1)
*(f1::Biquad, fs::Biquad...) = SecondOrderSections([f1, fs...], 1)
*(f1::SecondOrderSections, f2::Biquad) = SecondOrderSections([f1.biquads; f2], f1.g)
*(f1::Biquad, f2::SecondOrderSections) = SecondOrderSections([f1; f2.biquads], f2.g)
