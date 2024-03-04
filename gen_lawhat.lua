if not package.path:match"%./%?%.lua" then
    package.path = package.path .. ";./?.lua"
end
require"vec"
require"fit_curve"
require"common"

-- No idea what to put here. This number is 0.6 arc minutes 
-- (the typical human visual acuity) times 28 inches (the
-- nominal arm length). And then divide it by 3 for "good
-- measure". This is quite arbitrary but I had to arbitrate 
-- something!
draw_tol = 0.333*0.125 -- mm

line_width = laser_kerf -- mm

------------------------

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

--------------------------

str1 = string.format([[
<svg viewBox="0 0 %f %f" width="%fmm" height="%fmm" xmlns="http://www.w3.org/2000/svg">
]],
        total_width, total_height,
        total_width, total_height
)
-- For my own sake, and also because ponoko gets confused
-- without an outline, draw an outline
str1 = str1 .. string.format([[
        <rect x="0" y="0" width="%f" height="%f" fill="none" stroke="pink" stroke-width="%f" />
]],
        total_width, total_height,
        laser_kerf
)
-- For my own sake, add an outline for the safe drawing area
str1 = str1 .. string.format([[
    <rect x="%f" y="%f" width="%f" height="%f" fill="none" stroke="orange" stroke-width="%f" />
]],
    draw_xoff, draw_yoff,
    draw_width, draw_height,
    laser_kerf
)

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
                remap_x(theta(azimuth_line(a,az,latitude)) + 180),
                remap_y(phi  (azimuth_line(a,az,latitude))) 
            }
        end,
        lower, 80,
        draw_tol
    )
    print(", used ", #segs, "curve segments")
    str1 = str1 .. segs_to_svg(segs, laser_kerf, false) .. "\n"
end

for el = 0,81,10 do
    io.write("Working on elevation line ", el)
    io.flush()
    local closed = (el+latitude) > 90
    segs = fit_function(
        function(a) 
            return {
                remap_x(theta(elevation_circle(a,el,latitude)) + 180),
                remap_y(phi  (elevation_circle(a,el,latitude))) 
            }
        end,
        -180, 180,
        draw_tol,
        closed
    )
    print(", used ", #segs, "curve segments")
    str1 = str1 .. segs_to_svg(segs, laser_kerf, closed) .. "\n"
end


-- Now draw a graduated line for the time of day, which I have been
-- (maybe incorrectly) calling the "Sidereal Time Scale"

-- I made a sketch that looked "decent" and then measured it
h_above_bottom   = 8   -- mm
hour_height      = 2.6 -- mm
half_hour_height = 1.8 -- mm
ten_min_height   = 1   -- mm

mm_per_min = draw_width/(24*60)
hour_width = mm_per_min * 60

for i = 1,24 do
    str1 = str1 .. string.format(
    [[
    <path 
        fill="none" stroke="black" stroke-width="%f" 
        stroke-linecap="square"
        d=" M %f,%f h %f v %f h %f " 
    />
    ]],
        line_width,
        draw_xoff+i*hour_width, draw_yoff+draw_height-h_above_bottom,
        -hour_width, hour_height, hour_width
    )
end

str1 = str1 .. "</svg>"

f = io.open("out/lawhat.svg", "wb")
f:write(str1)
f:flush()
f = nil

print("done")