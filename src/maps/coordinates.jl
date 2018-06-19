export to_bcoords, from_bcoords, arcintervals

#######################################################################################
## Arclengths
#######################################################################################
"""
    totallength(o::Obstacle)
Return the total boundary length of `o`.
"""
@inline totallength(o::Wall) = norm(o.ep - o.sp)
@inline totallength(o::Semicircle) = π*o.r
@inline totallength(o::Circular) = 2π*o.r

@inline totallength(bd::Billiard) = sum(totallength(x) for x in bd.obstacles)

#this function only exists because incidence_angle from raysplitting.jl only works
#if you pass the particle *before* collision, which I cannot do because of bounce!
function reflection_angle(p::AbstractParticle{T}, a::Obstacle{T})::T where {T}
    n = normalvec(a, p.pos)
    inverse_dot = clamp(dot(p.vel, n), -1.0, 1.0)
    φ = acos(inverse_dot)
    if cross2D(p.vel, n) < 0
        φ *= -1
    end
    return φ
end

"""
    arcintervals(bd::Billiard) -> s
Generate a vector `s`, with entries being the delimiters of the
arclengths of the obstacles of the billiard.
The arclength from `s[i]` to `s[i+1]` is the arclength spanned by
the `i`th obstacle.

`s` is used to transform an arc-coordinate `ξ` from local to global and
vice-versa. A local `ξ` becomes global by adding `s[i]` (where `i` is the
index of current obstacle). A global `ξ` becomes local by subtracting `s[i]`.

See also [`boundarymap`](@ref), [`to_bcoords`](@ref), [`from_bcoords`](@ref).
"""
function arcintervals(bd::Billiard{T, D}) where {T, D}
    intervals = SVector{D+1,T}(0, map(x->totallength(x), bd.obstacles)...)
    return cumsum(intervals)
end

################################################################################
## Coordinate systems
################################################################################
"""
    to_bcoords(pos, vel, o::Obstacle) -> ξ, sφ
Convert the real coordinates `pos, vel` to
boundary coordinates (also known as Birkhoff coordinates)
`ξ, sφ`, assuming that `pos` is on the obstacle.

`ξ` is the arc-coordinate, i.e. it parameterizes the arclength. `sφ` is the
sine of the angle between the velocity vector and the vector normal
to the obstacle.

The arc-coordinate `ξ` is measured as:
* the distance from start point to end point in `Wall`s
* the arc length measured counterclockwise from the open face in `Semicircle`s
* the arc length measured counterclockwise from the rightmost point
  in `Circular`s

See also [`arcintervals`](@ref) and [`from_bcoords`](@ref).
"""
to_bcoords(p::AbstractParticle, o::Obstacle) = to_bcoords(p.pos, p.vel, o)
function to_bcoords(pos::SV, vel::SV, o::Obstacle)
    # n = normalvec(a, p.pos)
    # prod = clamp(dot(p.vel, n), -1.0, 1.0)
    # φ = acos(prod)
    # cross2D(p.vel, n) < 0 && (φ *= -1)
    # sinφ = sin(φ)

    sinφ = cross2D(vel, n)
    ξ = _ξ(pos, o)
    return ξ, sinφ
end

_ξ(pos::SV, o::Wall) = norm(pos - o.sp)

function _ξ(pos::SV{T}, o::Semicircle{T}) where {T<:AbstractFloat}
    #project pos on open face
    chrd = SV{T}(-o.facedir[2],o.facedir[1])
    d = (pos - o.c)/o.r
    x = dot(d, chrd)
    r =  acos(clamp(x, -1, 1))*o.r
    return r
end

function _ξ(pos::SV{T}, o::Circular{T}) where {T<:AbstractFloat}
    d = (pos - o.c)/o.r
    r = acos(clamp(d[1], -1, 1))*o.r
    return r
end



"""
    from_bcoords(ξ, sφ, o::Obstacle) -> pos, vel
Convert the boundary coordinates `ξ, φs` on the obstacle to
real coordinates `pos, vel`.

This function is the inverse of [`to_bcoords`](@ref).
"""
function from_bcoords(ξ::T, sφ::T, o::Obstacle{T}) where {T}
    cφ = cos(asin(sφ))
    n = normalvec(obst, pos)
    vel = SV{T}(-n[1]*cφ + n[2]*sφ, -n[1]*sφ - n[2]*cφ)

    return real_pos(ξ, o), vel
end

"""
    real_pos(ξ, o::Obstacle)
Converts the arclength coordinate `ξ` relative to the obstacle `o` into a real space
position vector.
"""
real_pos(ξ, o::Wall) = o.sp + ξ*normalize(o.ep - o.sp)

function real_pos(ξ, o::Semicircle{T}) where T
    sξ, cξ = sincos(ξ/o.r)
    chrd = SV{T}(-o.facedir[2], o.facedir[1])
    return o.c - o.r*(sξ*o.facedir - cξ*chrd)
end

real_pos(ξ, o::Circular{T}) where T = o.c .+ o.r * SV{T}(cossin(ξ/o.r))




# Old Lukas function:
function from_bcoords(ξ, sφ, bd::Billiard{T}; return_obstacle::Bool = false,
                          intervals = arcintervals(bd)
                          ) where T

    abs(sφ) > 1 && throw(DomainError(sφ, "|sin φ| must not be larger than 1"))

    for (i, obst) ∈ enumerate(bd)

        if ξ <= intervals[i+1]
            pos = real_pos(ξ - intervals[i], obst)

            #calculate velocity
            cφ = cos(asin(sφ))
            n = normalvec(obst, pos)
            vel = SV{T}(-n[1]*cφ + n[2]*sφ, -n[1]*sφ - n[2]*cφ)

            return return_obstacle ? (pos, vel, i) : (pos, vel)
        end
    end

    throw(DomainError(ξ ,"ξ is too large for this billiard!"))
end
