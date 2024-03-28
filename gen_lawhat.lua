if not package.path:match"%./%?%.lua" then
    package.path = package.path .. ";./?.lua"
end
require"vec"
require"fit_curve"
require"common"

-- common.lua provides latitude/longitude/timezone, but
-- for fun add an argument to the script that will
-- override them

-- Coords in degrees, timezone in hours
other_cities = {
    ["Fredericton"] = {45.96,  66.64, -4}, -- From Google autoresult (timezone from memory)
    ["Montréal"]    = {45.50,  73.57, -5},
    ["Halifax"]     = {44.65,  63.57, -4},
    ["Ottawa"]      = {45.42,  75.70, -5},
    ["Moncton"]     = {46.09,  64.77, -4}, -- Wikipedia
    ["Inuvik"]      = {68.34, 133.72, -7}, -- Wikipedia
    ["Bogotá"]      = { 4.71,  74.07, -5}, -- Wikipedia
}

city_name = "Toronto"

if other_cities[arg[1]] then
    city_name = arg[1]
    latitude, longitude, time_zone = unpack(other_cities[arg[1]])
elseif arg[1] then
    error("Unrecognized city name")
end

calib_str = string.format(
    "Calibrated for %s (%.1f˚ N, %.1f˚ W, UTC%d)",
    city_name,
    latitude, 
    longitude,
    time_zone
)



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

------------------
-- SVG prologue --
------------------

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

---------------------------------
-- Azimuth and elevation lines --
---------------------------------

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
                remap_x(theta(azimuth_line(a,az,latitude)) + 180), -- FIXME: why is there a +180 here?
                remap_y(phi  (azimuth_line(a,az,latitude))) 
            }
        end,
        lower, 80,
        draw_tol
    )
    print(", used ", #segs, "curve segments")
    str1 = str1 .. segs_to_svg(segs, laser_kerf, false) .. "\n"

    local label_text
    local label_placement = 0
    if math.abs(az - 180) < 1e-3 then
        -- Special case for North azimuth line: draw it
        -- at the other end
        label_placement = 80
    end
    
    local label_pos_ra = theta(azimuth_line(label_placement,az,latitude)) + 180 -- FIXME: why is there a +180 here?
    local label_pos_de = phi  (azimuth_line(label_placement,az,latitude))

    local label_alignment = "middle"
    if az > 1e-3 and az < (180-1e-3) then
        label_alignment = "end"
    elseif az > (180+1e-3) and az < (360-1e-3) then
        label_alignment = "start"
    end

    -- FIXME: why did I have to do 180-az???
    local label_text = string.format("%.0f", angle_clamp(180-az))
    -- Some special cases just for fun
    if label_text == "0"   then label_text = "N"  end
    if label_text == "45"  then label_text = "NE" end
    if label_text == "90"  then label_text = "E"  end
    if label_text == "135" then label_text = "SE" end
    if label_text == "180" then label_text = "S"  end
    if label_text == "225" then label_text = "SW" end
    if label_text == "270" then label_text = "W"  end
    if label_text == "315" then label_text = "NW" end

    local label_size = 1.4 -- mm 
    local label_weight = "normal"
    if math.floor(180-az + 0.5) % 45 == 0 then
        label_size = 1.8 -- mm
        label_weight = "bolder"
    end
    
    str1 = str1 .. string.format([[
        <text x="%f" y="%f" fill="black" font-family="Helvetica,sans-serif" font-size="%f" font-weight="%s" alignment-baseline="hanging" text-anchor="%s">%s</text>
        ]],
        remap_x(label_pos_ra), remap_y(label_pos_de) + 0.2, -- nudge down
        label_size,
        label_weight,
        label_alignment,
        label_text
    )
end

for el = 0,81,10 do
    io.write("Working on elevation line ", el)
    io.flush()
    -- The elevation line is closed if its highest declination
    -- is less than 90. FIXME: I don't think this works in the
    -- Southern hemisphere. (But the whole design needs to be
    -- adjusted for the Southern hemisphere so that the time
    -- scales don't clobber the constellations you would care
    -- about)
    local highest_declination =  90 + (latitude-el)
    
    local closed = highest_declination < 90
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


----------------
-- Time scale --
----------------

-- Now draw a graduated line for the time of day, which I have been
-- calling the "Time Scale"

-- Top line, aligns with Mean Sun scale
str1 = str1 .. string.format([[
    <path d="M %f,%f h %f" stroke-width="%f" stroke="black" />
]],
    draw_xoff, time_of_day_scale_y, draw_width,
    laser_kerf
)

-- Bottom line, aligns with Daylight Savings scale
str1 = str1 .. string.format([[
    <path d="M %f,%f h %f" stroke-width="%f" stroke="black" />
]],
    draw_xoff, dst_scale_y, draw_width,
    laser_kerf
)

-- We need to correctly offset the Time Scale for Toronto's latitude.
-- It works like this: at noon in UTC+0 on the day of the equinox,
-- it is 7:00 am and our meridian is shifted according to Toronto's
-- longitude. This gives us the relative shift between our local sky
-- and the Time Scale
time_zone_offset = angle_clamp(longitude + time_zone*(360/24)) -- degrees
degrees_per_min = -360/(24*60) -- hmmm... needed to negate this?

label_size         = 1.4 -- mm
hour_tick_height   = (dst_scale_y - time_of_day_scale_y - label_size - 0.1)/2 -- mm
minute_tick_height = hour_tick_height*0.75 -- mm

for i = 0,23 do
    local hour_num = i%12
    if hour_num == 0 then hour_num = 12 end

    local hour_str = tostring(hour_num)
    if hour_num == 12 then
        hour_str = ((i<12) and "M" or "Noon")
    elseif i<10 then
        hour_str = hour_str .. "am"
    elseif i>12 and i<22 then
        hour_str = hour_str .. "pm"
    end

    local hour_angle = angle_clamp(i*60*degrees_per_min + time_zone_offset)

    local label_anchor = "middle"
    local label_base_align = "middle"
    
    str1 = str1 .. string.format([[
        <path d="M %f,%f v %f" stroke-width="%f" stroke-linecap="round" stroke="black" />
        <path d="M %f,%f v %f" stroke-width="%f" stroke-linecap="round" stroke="black" />
        <text x="%f" y="%f" text-anchor="%s" alignment-baseline="%s" font-family="Helvetica, sans-serif" font-size="%f">%s</text>
    ]],
        remap_x(hour_angle), time_of_day_scale_y, hour_tick_height,
        laser_kerf,
        remap_x(hour_angle), dst_scale_y, -hour_tick_height,
        laser_kerf,
        remap_x(hour_angle), (time_of_day_scale_y+dst_scale_y)/2,
        label_anchor, label_base_align,
        label_size,
        hour_str
    )

    -- Add tick marks every 10 minutes
    for j = 10,50,10 do
        local minute_angle = angle_clamp(hour_angle + j*degrees_per_min)
        str1 = str1 .. string.format([[
            <path d="M %f,%f v %f" stroke-width="%f" stroke="black" stroke-linecap="butt"/>
            <path d="M %f,%f v %f" stroke-width="%f" stroke="black" stroke-linecap="butt"/>
        ]],
            remap_x(minute_angle), time_of_day_scale_y, minute_tick_height,
            laser_kerf,
            remap_x(minute_angle), dst_scale_y, -minute_tick_height,
            laser_kerf
        )
    end
end

--------------------------------------
-- Lawhat is calibrated for Toronto --
--------------------------------------

str1 = str1 .. string.format([[
    <text font-family="Helvetica, sans-serif" font-size="1.4" x="%f" y="%f" text-anchor="middle" alignment-baseline="ideographic">%s</text>
]],
    draw_xoff + draw_width/2, draw_yoff+draw_height,
    calib_str
)

------------------------
-- Write the SVG data --
------------------------

str1 = str1 .. "</svg>"
print("out/lawhat_" .. city_name .. ".svg")
f = io.open("out/lawhat_" .. city_name .. ".svg", "wb")
f:write(str1)
f:flush()
f = nil

print("done")