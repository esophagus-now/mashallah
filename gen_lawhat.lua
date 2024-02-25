function dtab(t)
    if (type(t) ~= "table") then
        print("(not a table)")
        return
    end

    for k,v in pairs(t) do
        print(k,v)
    end
end

function printf(...)
    return(io.write(string.format(...)))
end


------------------------

total_width  = 91.9 -- mm
total_height = 53.8 -- mm
draw_width  = 85.9 -- mm
draw_height = 47.8 -- mm

draw_xoff = (total_width  - draw_width )/2
draw_yoff = (total_height - draw_height)/2

my_xmin = -180
my_xmax = 180
my_ymin = -90
my_ymax = 90
my_xrange = my_xmax - my_xmin
my_yrange = my_ymax - my_ymin

function remap_x(x)
    -- Want my_min to map to draw_xoff
    -- Want my_max to map to draw_xoff + draw_width
    return (x-my_xmin) * draw_width/my_xrange + draw_xoff
end

function remap_y(y, my_min, my_max)
    -- Want my_min to map to draw_yoff + draw_height
    -- Want my_max to map to draw_yoff
    return (y-my_ymin) * draw_height/-my_yrange + draw_yoff + draw_height
end

-- No idea what to put here. This number is 0.6 arc minutes 
-- (the typical human visual acuity) times 28 inches (the
-- nominal arm length). And then divide it by 3 for "good
-- measure". This is quite arbitrary but I had to arbitrate 
-- something!
draw_tol = 0.333*0.125 -- mm

-- Apparently your typical Vernier acuity is 27 microns, so
-- we'll use that as our line widths. I guess.
-- Well, that looks terrible, so quadruple it. I guess.
line_width = 4*0.027 -- mm

------------------------

-- Given a function f:R -> R^3, returns the x component of the
-- perspective transformation of f(t) onto the screen at z=0 
-- centered at the origin with the eye at (0,0,eye_z)
function persp_x(f, t, eye_z)
    local x,y,z = f(t)
    local scale = eye_z/(eye_z - z)
    return x*scale
end

function persp_y(f, t, eye_z)
    local x,y,z = f(t);
    local scale = eye_z/(eye_z - z)
    return y*scale
end

--------------------------

-- Elevation and latitude are given in degrees, and t is taken to
-- be degrees CCW around the viewer's zenith relative to celestial
-- North
function elevation_circle(t, elevation, latitude)
    local zenith_rad = math.rad(latitude)
    local zenith_x = math.cos(zenith_rad)
    local zenith_z = math.sin(zenith_rad)
    -- zenith_y is zero here
    -- printf("zenith = [%f, 0, %f]", zenith_x, zenith_z)
    
    local horizon = (latitude-90)
    local elv_above_horz_rad = math.rad(horizon+elevation)
    
    -- We start on the equator at (1,0,0), then rotate around y to
    -- get to the correct elevation, given the latitude.
    local base_x = math.cos(elv_above_horz_rad)
    local base_z = math.sin(elv_above_horz_rad)
    -- base_y is also zero here
    -- printf("base = [%f, 0, %f]", base_x, base_z)
    
    -- Now we can rotate this new vector by t degrees around the
    -- Zenith. This uses the Rodrigues rotation formula, simplified
    -- for this special case
    local t_rad = math.rad(t)
    local ct = math.cos(t_rad)
    local st = math.sin(t_rad)
    
    local b_dot_z = base_x*zenith_x + base_z*zenith_z
    
    local b_cross_z_y = base_z*zenith_x - base_x*zenith_z
    -- The other two components of the cross product are conveniently zero!
    
    return
        base_x*ct + zenith_x*b_dot_z*(1-ct),
        b_cross_z_y*st,
        base_z*ct + zenith_z*b_dot_z*(1-ct)
end

-- This function only meant for checking gainst the tropic 
-- of Capricorn for projections with the eye at the South
-- pole.
-- Returns (mintheta,maxtheta, closed). If mintheta is 0 
-- and 0, some error occurred. 
function elevation_circle_bounds(elevation, latitude)
    local capricorn_z = -math.sin(math.rad(23.5))
    local _,_,minz = elevation_circle(0, elevation, latitude)
    
    -- Whole circle can be drawn
    if (minz >= capricorn_z) then
        return 0, 360, true
    end
    
    -- Use binary search to find bound angle
    local l = 0;
    local r = 90;
    local m = (l+r)/2;

    -- Just to prevent infinite loops
    num_iters = 0;
    max_iters = 50;
    while((r-l)>1e-8 and num_iters < max_iters) do
        num_iters = num_iters + 1;
        
        _,_,z = elevation_circle(m, elevation, latitude)
        
        if (z <= capricorn_z) then
            -- Move l to the right
            l = m
        else
            -- Move r to the left
            r = m
        end
        
        m = (l+r)/2;
    end

    if (num_iters == max_iters) then
        print("Iteration cound exceeded");
        return 0,0,false
    end
    
    return m, 360-m, false
end

rmat_memo = {}
-- latitude is given in degrees. This applies a rotation
-- of -(90-latitude) degrees around the y-axis (this
-- uses the usual convention that the x-axis points
-- towards an azimuth of 0˚)
function latitude_rot(latitude)
    if rmat_memo[latitude] then
        return rmat_memo[latitude]
    end

    local d = math.rad(-(90-latitude))
    
    local ret = {
        math.cos(d), 0, -math.sin(d),
        0,           1, 0,
        math.sin(d), 0, math.cos(d)
    }

    rmat_memo[latitude] = ret

    return ret
end

-- Azimuth and latitude are given in degrees, and t is taken to
-- be degrees above the viewer's horizon
function azimuth_line(t, azimuth, latitude)
    local theta = math.rad(azimuth)
    local phi = math.rad(t)
    
    local x = math.cos(theta)*math.cos(phi)
    local y = math.sin(theta)*math.cos(phi)
    local z = math.sin(phi)

    local rmat = latitude_rot(latitude)

    -- Use our knowledge that the matrix doesn't modify Y
    local x2 = rmat[1]*x + rmat[3]*z
    local z2 = rmat[7]*x + rmat[9]*z

    return x2,y,z2
end

-- theta is in degrees. Dumb as hell but whatever
function angle_clamp(theta)
    while theta < 0 do
        theta = theta + 360
    end
    while theta > 360 do
        theta = theta - 360
    end

    return theta
end

atan2 = math.atan2 or math.atan

-- Returns angle in degrees for the "theta" part of the spherical
-- coordinates corresponding to (x,y,z). You could reasonably call
-- this "azimuth"
function theta(x,y,z)
    return math.deg(atan2(y,x))
    --return x
end
-- Same as above but for elevation
function phi(x,y,z)
    return math.deg(atan2(z,math.sqrt((x*x)+(y*y))))
    --return z
end

--------------------------

-- Try to be smart about skipping discontinuities
function segs_to_svg(segs, closed, stroke)
    local closed = closed or false -- Prevent nils in expressions
    local stroke = stroke or "black"

    -- conncected[i] is true if segs[i] connects to segs[i-1], with the 
    -- special case that connected[1] says whether we connect segs[1] to
    -- segs[#segs]
    local connected = vec{closed}
    -- Here we use equality testing for floats because we happen to know that
    -- our curve-fitting function uses exactly equal points for connected
    -- segments
    local start_idx = 1
    for i = 2,#segs do
        connected[i] = (
            (segs[i][1][1] == segs[i-1][4][1]) and 
            (segs[i][1][2] == segs[i-1][4][2])
        )
        if not connected[i] then start_idx = i end
    end
    
    local ret = string.format([[<path fill="none" stroke="%s" stroke-width="%f" d="]], stroke, line_width)
    for i = start_idx,start_idx+#segs-1 do
        local idx = i
        if idx > #segs then idx = idx - #segs end

        local seg = segs[idx]

        if (i == start_idx) or not connected[i] then
            ret = ret .. "M " .. seg[1][1] .. "," .. seg[1][2]
        end
        
        ret = ret .. " C "
        for j = 2,4 do
            ret = ret .. seg[j][1] .. "," .. seg[j][2] .. " "
        end
    end

    if connected[start_idx] then
        ret = ret .. " z "
    end
    
    ret = ret .. "\"/>\n"

    return ret
end

latitude = 43.65 -- 43.65 degrees for Toronto
str1 = string.format([[
<svg viewBox="0 0 %f %f" width="%fmm" height="%fmm" xmlns="http://www.w3.org/2000/svg">
]],
        total_width, total_height,
        total_width, total_height
)

if not package.path:match"%./%?%.lua" then
    package.path = package.path .. ";./?.lua"
end
require"vec"
require"fit_curve"

for az = 0,359,(360/24) do
    io.write("Working on azimuth line ", az)
    io.flush()
    local lower = 0
    if math.abs(az-180) < 0.1 then
        lower = latitude + 0.05
    end
    segs = fit_function(
        function(a) 
            return {
                remap_x(theta(azimuth_line(a,az,latitude))),
                remap_y(phi  (azimuth_line(a,az,latitude))) 
            }
        end,
        lower, 80,
        draw_tol
    )
    print(", used ", #segs, "curve segments")
    str1 = str1 .. segs_to_svg(segs, false) .. "\n"
end

for el = 0,81,10 do
    io.write("Working on elevation line ", el)
    io.flush()
    local closed = (el+latitude) > 90
    segs = fit_function(
        function(a) 
            return {
                remap_x(theta(elevation_circle(a,el,latitude))),
                remap_y(phi  (elevation_circle(a,el,latitude))) 
            }
        end,
        -180, 180,
        draw_tol,
        closed
    )
    print(", used ", #segs, "curve segments")
    str1 = str1 .. segs_to_svg(segs, closed) .. "\n"
end

str1 = str1 .. "</svg>"

f = io.open("out/lawhat.svg", "wb")
f:write(str1)
f:flush()
f = nil

print("done")