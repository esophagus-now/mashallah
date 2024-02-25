--[[
Usage:

fit_function takes an arbitrary function that maps a single float 
to an output in R^n. The output of this function can be a single 
number, a table, or a vec. You also give fit_function the range to 
sweep over and the desired tolerance.

fit_curve is very similar to fit_function, but instead of a function
you give it an array of points. (Actually, fit_function uses this
behind the scenes)

The left_tangent, right_tangent, and center_tangent methods may be
usable in general to approximate tangent directions on a discrete
list of points in R^n.

--]]

if not package.path:match"%./%?%.lua" then
    package.path = package.path .. ";./?.lua"
end
require"vec"

-- Given a list of 2D vectors, return a list of time parameter values for each
-- point. These times range from 0 to 1 and t[i+1]-t[i] is proportional to
-- the squared distance between arr[i+1] and arr[i]
function chordal_paramn(arr, alpha)
    local alpha = alpha or 1
    local dists = setmetatable({0}, vec_mt)
    for i = 2,#arr do
        dists[i] = dists[i-1] + math.pow(vec_mt.norm(arr[i]-arr[i-1]), alpha)
        assert(dists[i] > 1e-8) -- TODO deal with this in a smarter way
    end

    for i = 2,#arr do
        dists[i] = dists[i] / dists[#arr]
    end
    
    return dists
end

-- For each element of t, compute the four Bézier weights in the
-- usual way: [(1-t)^3, 3t(1-t)^2, 3t^2(1-t), t^3] and return 
-- this as four lists, each the same size as t
function bez3(t)
    local b0 = setmetatable({}, vec_mt)
    local b1 = setmetatable({}, vec_mt)
    local b2 = setmetatable({}, vec_mt)
    local b3 = setmetatable({}, vec_mt)

    for i,v in ipairs(t) do
        assert(0<=v and v<=1, "paramter value should be between 0 and 1")
        assert(i == 1 or t[i-1]<v, "parameter values should be increasing")
        
        local omv  = 1-v
        local omv2 = omv*omv
        local omv3 = omv*omv2
        local v2 = v*v
        local v3 = v*v2
        b0[i] = omv3
        b1[i] = 3*v*omv2
        b2[i] = 3*v2*omv
        b3[i] = v3
    end

    return b0,b1,b2,b3
end

-- Uses the first three points to approximate the tangent direction
-- at the first point. Returns a normalized direction. Assumes the 
-- points are all unique and in "ascending order"
function left_tangent(p)
    -- This is Neville's algorithm special-cased for three points
    -- where our sample location coincides with the first point
    local dp1 = p[2]-p[1]
    local dp2 = p[3]-p[2]
    local dt1 = dp1:norm()
    local dt2 = dp2:norm()
    assert(dt1>1e-8 and dt2>1e-8, "Points are too close together, " .. tostring(p[1]) .. " " .. tostring(p[2]) .. " " .. tostring(p[3]))
    
    -- Formula: 
    -- Using the same notation as on https://en.wikipedia.org/wiki/Neville%27s_algorithm
    -- and using lerp(t,tl,tr,yl,yr) to mean "the linear interpolation between (tl,yl) and
    -- (tr,yr) at t"
    -- p'01 = (p[1]-p[0])/dt1
    -- p'12 = (p[2]-p[1])/dt2
    -- p01  = lerp(t=0,tl=0,  tr=dt1,    p[0],p[1]) = p[0]
    -- p12  = lerp(t=0,tl=dt1,tr=dt1+dt2,p[1],p[2]) = lerp(t=-dt1,tl=0,tr=dt2,p[1],p[2]) = p[1]-p'12*dt1
    -- p'02 = lerp(t=0,tl=0,  tr=dt1+dt2,p'01,p'12) + (p12-p01)/(dt1+dt2) = p'01 + (p[1] - p'12*dt1 - p[0])/(dt1+dt2)

    local pp1 = dp1/dt1
    local pp2 = dp2/dt2

    --print("pp1", pp1[2]/pp1[1])
    --print("pp2", pp2[2]/pp2[1])
    --print("p1 ", p[2])
    --print("p12", p[2] - pp2*dt1)

    local dir = pp1 + (dp1 - pp2*dt1)/(dt1+dt2)
    return dir/dir:norm()
end

-- I had a totally unjustified intuition that this could work. We'll try it out lol
function right_tangent(p)
    local N = #p
    assert(N>=3)
    return left_tangent{p[N],p[N-1],p[N-2]}
end

-- Approximate tangent direction at point p[idx]. Assumes points
-- are unique and "in order". Returns a normalized direction.
-- My intuition tells me you just lerp the two secant slopes
function center_tangent(p, idx)
    assert(idx > 1 and idx < #p)
    local dp1 = p[idx]   - p[idx-1]
    local dp2 = p[idx+1] - p[idx]
    local dt1 = dp1:norm()
    local dt2 = dp2:norm()
    assert(dt1>1e-8 and dt2>1e-8, "While approximating center tangent: points are too close together")

    local L = dt1+dt2

    local dir = (dp1*dt2 + dp2*dt1)/L

    return dir/dir:norm()
end

-- Returns a list where each element is a list of the four control
-- points for a Bézier curve. We guarantee that the points in the 
-- given array are never farther than tol away from the closest 
-- curve point.
-- Adapted from Graphics Gems
function fit_segments(p, tol, dl, dr, closed)
    assert(#p>1)

    setmetatable(p, vec_mt)
    --print("\nFitting to", p, dl, dr)
    
    -- Special case for two points
    if #p == 2 then
        --print"Special case #p == 2"
        local dp = vec_mt.norm(p[2]-p[1])
        if not dl or not dr then
            dl = (p[2]-p[1])/dp
            dr = -dl
        end
        assert(dp > 1e-8)
        return vec{
            vec{p[1], p[1]+dl*dp/3, p[2]+dr*dp/3, p[2]}
        }
    end

    -- If the caller didn't give us tangents, try to
    -- guess them
    if not dl or not dr then
        if closed then
            local last_point = p[#p]
            -- Sometimes the user's last point is the same as the first,
            -- and sometimes the user just wants us to bridge the gap. 
            -- Try to DTRT
            if vec_mt.norm(last_point - p[1]) < 1e-8 then
                assert(#p>=4, "Doesn't make sense to take center tangent at a cusp. Your three curve-defining points have two of them equal")
                last_point = p[#p-2]
            end
            local t = {last_point,p[1],p[2]}
            dl = center_tangent(t,2)
            dr = -dl
        else
            dl = left_tangent(p)
            dr = right_tangent(p)
        end
    end
    
    -- We start with a chordal parameterization of our points. We'll
    -- use Newton's method to improve this.
    local t = chordal_paramn(p, 0.5) -- alpha=0.5 gives centripetal parameterization. 
                                     -- Improves results for reasons I don't understand
    --print(t)

    local ret;

    local num_iters = 0
    local MAX_ITERS = 32

    local last_total_sqerr = 1e8 -- Some random huge number
    
    while true do
        --print"------------------------"
        --print("t", t)
        -- Bézier coefficients for each t
        local b0, b1, b2, b3 = bez3(t)
        
        -- Algebra is a little easier to deal with if you use the
        -- linearity of bezier segments. In other words, if c1 and
        -- c2 are two sets of control points and B returns the
        -- polynomial representing the curve,
        -- B(c1+c2) = B(c1) + B(c2)

        -- This lets us subtract off B({p1,p1,pn,pn}) meaning that
        -- we're fitting a curve segment that always starts and ends
        -- at 0,0. This does simplify the expressions, though it
        -- comes at the cost of this extra computation, so who 
        -- knows if it actually saves performance...
        
        local p_twiddle = {}
        for i = 1,#p do
            p_twiddle[i] = p[i] - ((b0[i]+b1[i])*p[1] + (b2[i]+b3[i])*p[#p])
        end

        -- We are going to find a set of control points that satisfies
        -- c = {0, alpha_l*dl, alpha_r*dr, 0}, where alpha_l and alpha_r
        -- are scalars, and dl and dr are the (normalized) tangent
        -- directions at the endpoints.

        -- You obtain the following system of linear equations by
        -- writing an expression for the sum of squared errors and 
        -- setting its derivative to zero. Here is the expression 
        -- for the derivative of squared error at a single point,
        -- just in case you're interested:
        --
        -- +-           -+    +-                                             -+ +-       -+    +-                           -+
        -- | dEi/alpha_l |    | b1[i]*b1[i]*dot(dl,dl) b1[i]*b2[i]*dot(dl,dr) | | alpha_l |    | b1[i]*dot(p_twiddle[i], dl) |
        -- | dEi/alpha_r | = 2| b1[i]*b2[i]*dot(dl,dr) b2[i]*b2[i]*dot(dr,dr) | | alpha_r | - 2| b2[i]*dot(p_twiddle[i], dl) |
        -- +-           -+    +-                                             -+ +-       -+    +-                           -+

        -- Anyway, adding up the derivative of squared error for each 
        -- point and setting to 0 gives:

        -- Some helper vars
        local dll = dl..dl
        local dlr = dl..dr
        local drr = dr..dr
        local b11 = b1..b1
        local b12 = b1..b2
        local b22 = b2..b2
        local sum_b1_p_twiddle = vec{0,0}
        local sum_b2_p_twiddle = vec{0,0}
        for i = 1,#p_twiddle do
            sum_b1_p_twiddle = sum_b1_p_twiddle + b1[i]*p_twiddle[i]
            sum_b2_p_twiddle = sum_b2_p_twiddle + b2[i]*p_twiddle[i]
        end

        -- Put together our system of equations to solve
        A = {
            {b11*dll, b12*dlr},
            {b12*dlr, b22*drr}
        }
        b = {
            sum_b1_p_twiddle..dl,
            sum_b2_p_twiddle..dr
        }

        -- Solve! As much as I dislike determinants, Cramer's
        -- rule is probably the nicest solution for a 2x2
        -- system. Plus it gives us a free way to assert that
        -- the matrix is solvable
        local det = A[1][1]*A[2][2] - A[1][2]*A[2][1]
        assert(math.abs(det) > 1e-8, "Can't find a solution or something")

        local alpha_l = (b[1]*A[2][2] - A[1][2]*b[2])/det
        local alpha_r = (A[1][1]*b[2] - b[1]*A[2][1])/det

        -- Now we compute the error to see if we're done, or if
        -- we need an iteration of Newton's method. If the error
        -- is "really bad" then we will split into multiple
        -- segments.

        local total_sqerr = 0
        local max_sqerr = 0
        local max_sqerr_idx = -1
        local err = vec{} -- save this so we don't recompute it later
        for i = 1,#t do
            local B = alpha_l*dl*b1[i] + alpha_r*dr*b2[i]
            err[i] = B - p_twiddle[i] -- Note: p_twiddle = (p - B_twiddle), so
                                      -- this err = B - (p - B_twiddle), which
                                      -- is equal to (B+B_twiddle) - p. This is
                                      -- exactly equal to the final curve value at
                                      -- this time point minus the original point.
            local sqerr = err[i]..err[i]
            total_sqerr = total_sqerr + sqerr
            if sqerr > max_sqerr then
                max_sqerr = sqerr
                max_sqerr_idx = i
            end
        end

        -- local err_norm = vec{}
        -- for i,v in ipairs(err) do err_norm[i] = v:norm() end
        --print("err", err_norm)
        --print("max", math.sqrt(max_sqerr))
        --print("total_sq", total_sqerr)

        -- Trick from graphics gems: if error is too big to begin with, don't bother wasting
        -- computer time on something that probably won't converge
        if max_sqerr > 100*tol*tol or num_iters >= MAX_ITERS or total_sqerr >= 0.99 * last_total_sqerr then
            --print"Not converging. Give up and split."
            local left_pts = {}
            local right_pts = {}
            for i = 1,max_sqerr_idx do
                table.insert(left_pts,p[i])
            end
            for i = max_sqerr_idx,#p do
                table.insert(right_pts,p[i])
            end
            local tangent = center_tangent(p, max_sqerr_idx)
            local ret = fit_segments(left_pts, tol, dl, -tangent, false)
            local right_curve_segs = fit_segments(right_pts, tol, tangent, dr, false)
            for _,seg in ipairs(right_curve_segs) do
                table.insert(ret,seg)
            end
            return ret
        elseif max_sqerr < tol*tol then
            -- Within desired tolerance
            --print"Met tolerance"
            
            -- Only returning one curve segment, but this fn is always advertised
            -- as returning a list of segments, so return a list of length 1
            return vec{ vec{p[1],p[1]+alpha_l*dl,p[#p]+alpha_r*dr,p[#p]} }
        end

        last_total_sqerr = total_sqerr
        
        num_iters = num_iters + 1
        --print("Iteration", num_iters)
        assert(num_iters <= MAX_ITERS, "Exceeded maximum number of iterations to converge spline parameterization")
        
        -- Do an iteration of Newton's method to reparameterize our t values
        -- For each point in our list, there is a closest point to it on the
        -- fitted curve that has the property:
        --
        -- dot(p[i] - B(t_closest), B'(t_closest)) = 0
        --
        -- Newton's method is t_new = t_old - f(t_old)/f'(t_old). Here we have
        -- f(t) = dot(B(t) - p[i], B'(t)), so:
        --
        -- t_new = 
        --     t_old - (
        --         dot(B(t_old)-p[i], B'(t_old)) / 
        --         (dot(B(t_old)-p[i], B''(t_old)) + dot(B'(t_old), B'(t_old)))
        --     )
        -- ;

        for i = 2,#t-1 do
            
            -- d/dt 3t(1-t)^2 = 3(1-t)^2 - 6t(1-t),  d2/dt2 = -6(1-t) - 6(1-t) + 6t = 6t - 12(1-t)
            -- d/dt 3t^2(1-t) = 6t(1-t)  - 3t^2,     d2/dt2 = 6(1-t) - 6t - 6t      = 6(1-t) - 12t
            local ti = t[i]
            local tt = ti*ti 
            local u = 1-ti
            local uu = u*u
            local common_exp = 6*ti*u
            local b0_prime = -3*uu
            local b1_prime = 3*uu - common_exp
            local b2_prime = common_exp - 3*tt
            local b3_prime = 3*tt
            local b0_prime_prime = 6*u --Putting _prime_prime is funny to me for some reason
            local b1_prime_prime = 6*ti - 12*u 
            local b2_prime_prime = 6*u  - 12*ti
            local b3_prime_prime = 6*ti

            local c0 = p[1]
            local c1 = p[1]  + alpha_l*dl
            local c2 = p[#p] + alpha_r*dr
            local c3 = p[#p]
            
            local B_prime       = c0*b0_prime       + c1*b1_prime       + c2*b2_prime       + c3*b3_prime
            local B_prime_prime = c0*b0_prime_prime + c1*b1_prime_prime + c2*b2_prime_prime + c3*b3_prime_prime

            -- Alas... lua concat has lower precedence than arithmetic. Oh well.
            local num   = err[i]..B_prime
            local denom = (err[i]..B_prime_prime) + (B_prime..B_prime)
            if math.abs(denom) > 1e-8 then
                t[i] = ti - num / denom
            end 
        end
    end 
end

-- Takes in a list of vectors and returns a new list that removes
-- points less than tol (default 1e-8) away from the previous point. 
-- If you pass a truthy value for avg, then instead of deleting one
-- of the points we'll average them
function remove_duplicates(p, tol, closed, avg)
    local tol = tol or 1e-8
    local ret = vec{p[1]}
    for i = 2,#p do
        local dist = vec_mt.norm(p[i] - p[i-1])
        if dist > tol then
            table.insert(ret, p[i])
        elseif avg then
            ret[#ret] = 0.5*(p[i] + p[i-1]) -- TODO: is there are more numerically stable way to do this?
        end
    end

    return ret
end

-- Returns a list of vectors, where each list is "smooth enough".
-- If we originally had a list that went [a, b, c, d, e, f] and
-- we detected a corner at c, then the result would be
-- [[a,b,c], [c, d, e, f]]. Observe that element c appears in 
-- both lists. All returned lists will have 2 or more elements
-- (and we return just the original array if it has 2 or fewer
-- elements to begin with).
-- We define "smooth enough" to mean "the angle formed by any
-- three consecutive points is within some tolerance around 180". 
-- tol is an angle in radians
function split_at_corners(arr, tol)
    local tol = tol or 0.75 -- 0.75 radians is about 45 degrees
    if #arr < 3 then
        return {arr}
    end

    local darr = setmetatable({},mt_vec)
    for i = 1,#arr-1 do
        local diff = arr[i+1] - arr[i]
        darr[i] = diff/diff:norm()
    end

    split_posns = vec{1}
    for i = 2,#arr-1 do
        local ctheta = (darr[i-1]..darr[i])
        local theta = math.acos(ctheta)
        --print("theta", theta)
        if math.abs(theta) > tol then
            table.insert(split_posns,i)
        end
    end
    table.insert(split_posns, #arr)

    -- print("split posns", split_posns)

    local ret = {}

    for i = 1,#split_posns-1 do
        local l,r = split_posns[i], split_posns[i+1]
        local cur = {}
        for j = l,r do
            table.insert(cur, arr[j])
        end
        table.insert(ret, cur)
    end

    return ret
end

-- Wrapper around fit_segments. It has the same signature, but preprocesses the
-- input to remove corners and "potentially duplicated" points (i.e. points that
-- are really really close to each other). 
-- MM Feb 24 / 2024: This function adds a parameter connect_dcs that defaults to
-- false. If it is truthy, then we will draw a line between disconnected curve
-- segments
function fit_curve(p, tol, dl, dr, closed, connect_dcs)
    local p = remove_duplicates(p, tol*1e-2, closed) -- Not sure if tol/100 makes sense, but whatever
    --print("num unique pts", #p)
    if #p > 15000 then
        print(string.format("Warning: you are fitting curves to over 15000 samples (you have %d samples), which can be quite slow. Be patient!", #p))
    end
    local parts = split_at_corners(p, 0.75) -- about 45 degrees, seems to give good results
    --print("num parts", #parts)
    local ret = vec{}
    for i,part in ipairs(parts) do
        local is_dc = true -- Guilty until proven innocent
        -- This curve part represents a discontinuity when it
        -- has exactly two elements. However, in the "corner 
        -- case" (hehe) that the user has a bunch of adjacent 
        -- line segments, we'll draw it anyway. 
        -- MM Feb 24 / 2024: Fix another corner case where we
        -- only return a single line segment
        if 
            (#part > 2) or
            (i > 1 and #parts[i-1] == 2) or
            (i < #parts and #parts[i+1] == 2) or
            #parts == 1
        then
            is_dc = false
        end
        
        -- If we're connecting discontinuities, or if this isn't
        -- a discontinuity, fit the curve segments and return them
        if connect_dcs or not is_dc then
            local segs = fit_segments(part, tol, dl, dr, closed)
            for _,seg in ipairs(segs) do
                table.insert(ret, seg)
            end
        end
    end

    return ret
end

-- Return three sequences T,Y,D where:
--  - Y[i] = f(T[i])
--  - if D[i] is false, then sqdist(Y[i], Y[i+1]) <= dmax^2
--  - if D[i] is true, then it indicates that there is a discontinuity between Y[i] and Y[i+1]
--  - T[i] < T[i+1]
--  - T[0] = t0
--  - T[end] = t1
--  - Note that we do not enforce equally-spaced ts in the T array.
-- You can optionally provide your own squared distance function
function sample_max_spacing(f, t0, t1, dmax, sqdist, max_strikes)
    local max_strikes = max_strikes or 5
    
    if t0 > t1 then t0,t1 = t1,t0 end

    local ft0 = vec(f(t0))
    local ft1 = vec(f(t1))

    local sqdmax = dmax * dmax

    if not sqdist then
        sqdist = function(a,b) return vec_mt.norm(a-b) end
    end

    local pts = {{t0,ft0,false}, {t1,ft1,false}}
    function recur(pt0, pt1, last_sqdist, strikes)
        -- If called, it means last_sqdist is too big, so add the midpoint to the list of outputs
        -- MM Feb 24 / 2024: To prevent spurious failures when sampling a function that starts
        -- and ends at the same point, we no longer enforce that the recur function was called
        -- because the spacing was too big
        -- assert(last_sqdist > sqdmax)
        assert(pt0[1] < pt1[1])
        local tm = (pt0[1]+pt1[1])/2
        local ftm = vec(f(tm))
        local ptm = {tm, ftm, false}
        table.insert(pts, ptm)

        local lsqdist = sqdist(pt0[2], ftm)
        local rsqdist = sqdist(ftm, pt1[2])

        if lsqdist > sqdmax then
            local strikes_next = (lsqdist >= last_sqdist*0.9) and strikes + 1 or 0
            if strikes_next == max_strikes then
                pt0[3] = true
            else
                recur(pt0, ptm, lsqdist, strikes_next)
            end
        end

        if rsqdist > sqdmax then
            local strikes_next = (rsqdist >= last_sqdist*0.9) and strikes + 1 or 0
            if strikes_next == max_strikes then
                ptm[3] = true
            else
                recur(ptm, pt1, rsqdist, strikes_next)
            end
        end
    end

    local init_sqdist = sqdist(ft0, ft1)
    -- MM Feb 24 / 2024: Always call the recurrent function at least once to
    -- prevent spruious early returns on functions that start and end at the
    -- same spot
    recur(pts[1],pts[2],init_sqdist,0)

    -- Re-order points into final returned arrays
    table.sort(pts,
        function(a,b)
            return a[1] < b[1]
        end
    )

    -- Could be more efficient if we pre-allocated but whatever
    local T,Y,D = {},{},{}
    for i,pt in ipairs(pts) do
        T[i] = pt[1]
        Y[i] = pt[2]
        D[i] = pt[3]
    end

    return T,Y,D
end

-- Fits curves to draw the given function f to within tol. Specifically,
-- this guarantees that the returned curve is no more than tol away from
-- the nearest point on f. The function can return numbers, tables, or
-- vectors (using vec_mt from vec.lua). Passing in a truthy value for 
-- closed will enforce G1 continuity across the endpoints t0 and t1. If
-- you do not provide a tolerance, we try to guess something reasonable
-- by probing the function in a few places
function fit_function(f, t0, t1, tol, closed)
    if not tol then
        -- Try to guess a reasonable tolerance. There's no generally good
        -- way to do this, but we can try probing the function in a few 
        -- spots to get an idea of its "spread". This method can be defeated
        -- if the function is periodic, but hey, what can you do?
        local test_pts = {}
        for t = t0,t1,(t1-t0)/6 do
            table.insert(test_pts, vec(f(t)))
        end

        local max_dist = 0
        for i = 1,#test_pts do
            for j = i+1,#test_pts do
                local dist = vec_mt.norm(test_pts[j] - test_pts[i])
                if dist > max_dist then max_dist = dist end
            end
        end

        tol = math.max(1e-8,max_dist * 3e-4) -- Don't use ultra-small tolerances, I guess. Also, this 3e-4 is just a wild guess that seems OK
    end

    local _,samples = sample_max_spacing(f, t0, t1, 10*tol) -- 10*tol seems to give good results? idk
    -- print("Num samples ", #samples)
    return fit_curve(samples, tol, nil, nil, closed)
end




-- Random test code
--[==[

function whatever(t)
    local ret = vec{105,205} + 100*vec{math.sin(2*t),math.cos(t) + math.cos(3*t/7)}
    if t > 10*math.pi then
        ret = ret + vec{20,20}
    end
    return ret
end

--pts = vec{}
--for t = 0,20*math.pi+0.1,0.005 do
--    table.insert(pts, whatever(t))
--end
--_,pts = sample_max_spacing(whatever, 0, 20*math.pi, 1)

segs = vec(fit_function(whatever, 0, 20*math.pi))

--print("#pts, #segs", #pts, #segs)
print("#segs", #segs)

f = io.open("out/curve_test.svg", "wb")
f:write[[
<svg xmlns="http://www.w3.org/2000/svg">
]]

for i,seg in ipairs(segs) do
    if i%2 == 0 then
        f:write[[<path fill="none" stroke="black" d="]]
    else
        f:write[[<path fill="none" stroke="red" d="]]
    end

    f:write("M ", seg[1][1], ",", seg[1][2], " ")
    
    f:write"C "
    for j = 2,4 do
        f:write(seg[j][1], ",", seg[j][2], " ")
    end

    f:write"\"/>\n"
end

f:write"</svg>\n"
f:close()

--]==]