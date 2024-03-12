if not package.path:match"%./%?%.lua" then
    package.path = package.path .. ";./?.lua"
end
require"vec"
require"fit_curve"
require"common"
require"constellation_lut"
require"ldb"

-----------------------
-- Read in star data --
-----------------------
f = assert(io.open"bsc5.dat")
tab = {}
for l in f:lines() do
    local mag = tonumber(l:sub(103,107))

    if mag then
        local rah = assert(tonumber(l:sub(76,77)))
        local ram = assert(tonumber(l:sub(78,79)))
        local ras = assert(tonumber(l:sub(80,83)))
        local ra_deg = 360 * (60*(60*rah+ram)+ras) / (24*60*60)

        local desgn = l:sub(84,84)
        local ded = assert(tonumber(l:sub(85,86)))
        local dem = assert(tonumber(l:sub(87,88)))
        local des = assert(tonumber(l:sub(89,90)))
        local de_deg = ded + (dem + des/60)/60
        if desgn == "-" then de_deg = -de_deg end

        table.insert(tab, {mag, ra_deg, de_deg})
    end
end

table.sort(tab, function(a,b) return a[1] < b[1] end)
f:close()

--------------------------------
-- SVG tag and bounding boxes --
--------------------------------

f = io.open("out/ankabut.svg", "wb")

f:write(string.format([[
<svg viewBox="0 0 %f %f" width="%fmm" height="%fmm" xmlns="http://www.w3.org/2000/svg">
]],
        total_width, total_height,
        total_width, total_height
))

-- To help me cut out the pieces, draw lines on the cuts
f:write(string.format([[
        <path d="M 0,0 h %f m 0,%f h -%f" fill="none" stroke="pink" stroke-width="%f" />
]],
        total_width, total_height, total_width,
        laser_kerf
))

-- For my own sake, add an outline for the safe drawing area
f:write(string.format([[
    <rect x="%f" y="%f" width="%f" height="%f" fill="none" stroke="orange" stroke-width="%f" />
]],
    draw_xoff, draw_yoff,
    draw_width, draw_height,
    laser_kerf
))


-------------------------
-- Draw constellations --
-------------------------

-- Draw the lines first so that other things are drawn on top

function add_line(x1, y1, x2, y2)
    f:write(string.format([[
        <path stroke="gray" stroke-width="%f" stroke-linecap="round" d="M %f,%f L %f,%f"/>
    ]],
        dot_size,
        remap_x(tonumber(x1)),
        remap_y(tonumber(y1)),
        remap_x(tonumber(x2)),
        remap_y(tonumber(y2))
    ))
end

-- Dominic Ford is the man!
cdat = assert(io.open"constellation_stick_figures.dat")
for l in cdat:lines() do
    if not l:match"#" then
        local c, ra_start, de_start, ra_end, de_end = 
            l:match("(%w+)%s+" .. string.rep("([0-9%.-]+)%s*", 4))
        ;

        if c then
            -- Check if this line segment intersects with RA=0
            ra_start = angle_clamp(assert(tonumber(ra_start)))
            de_start =             assert(tonumber(de_start))
            ra_end   = angle_clamp(assert(tonumber(ra_end)))
            de_end   =             assert(tonumber(de_end))

            -- Just to simplify the next bit of logic, make end>start
            if ra_end < ra_start then
                ra_start,ra_end = ra_end,ra_start
                de_start,de_end = de_end,de_start
            end

            -- There are always two ways to draw a line between two
            -- coordinates (since we're technically on the surface
            -- of a sphere). Always pick the shorter one
            local dra = ra_end-ra_start
            if dra > 180 then
                -- Draw from end to start. We know this will
                -- cross the RA=0 axis, so find the point of
                -- intersection and draw two lines
                local slope = (de_start-de_end)/angle_clamp(ra_start-ra_end)
                local de_at_intersection = de_end + slope*(360-ra_end)

                add_line(ra_end,de_end,360,de_at_intersection)
                add_line(0,de_at_intersection,ra_start,de_start)
            else
                -- Draw from start to end
                add_line(ra_start,de_start,ra_end,de_end)
            end


        end
    end
end

cdat:close()

-----------------------
-- Draw the ecliptic --
-----------------------

-- Inspired by the method in Alejandro Jenkins's "The Position of
-- the Sun in the Sky".This function takes the degree angle along 
-- the ecliptic (starting from the March equinox) and returns the 
-- same RA and DEC coordinates we're using everywhere else
function ecliptic_raw(theta)
    local gamma = -math.rad(axial_tilt)
    local stheta = math.sin(math.rad(theta))
    local ctheta = math.cos(math.rad(theta))
    return vec{
        angle_clamp(math.deg(atan2(
            math.cos(gamma)*stheta,
            ctheta
        ))),
        math.deg(math.asin(-math.sin(gamma)*stheta))
    }
end
function ecliptic(theta)
    local raw = ecliptic_raw(theta)
    return vec{remap_x(raw[1]), remap_y(raw[2])}
end

io.write("Working on ecliptic ")
io.flush()
segs = fit_function(
    ecliptic,
    5, 365,
    draw_tol,
    true
)
print(", used ", #segs, "curve segments")
f:write(segs_to_svg(segs, laser_kerf, true, "green") .. "\n")
-- Now add tick markers on the ecliptic for dates

-- This is a COMPLETELY STOLEN function from Alejandro Jenkins's
-- "The Sun's Position in the Sky". That is a really great article,
-- I recommend reading it
-- d is the time in 24 hour days past Jan 1 2013 midnight UTC. 
-- Returns angle in degrees around the ecliptic measured from 
-- the March equinox
function true_anomaly(d,mean)
    local q = mean and 0 or 1
    local M = -0.0410 + 0.017202*d -- rad
    local theta_E = (
        -1.3411 + M + q*0.0334*math.sin(M) + q*0.0003*math.sin(2*M)
    ) -- rad
    return math.deg(theta_E)
end

months = {
    {"Ja", 31},
    {"Fe", 28},
    {"Mr", 31},
    {"Ap", 30},
    {"May", 31},
    {"Jn", 30},
    {"Jl", 31},
    {"Au", 31},
    {"Se", 30},
    {"Oc", 31},
    {"No", 30},
    {"De", 31}
}

d = 0
for _,m in ipairs(months) do
    local ta = true_anomaly(d)
    local tick_pos = ecliptic(ta)
    local tick_height = 0.8 -- mm

    f:write(string.format([[
        <path stroke="green" stroke-width="%f" stroke-linecap="round" d="M %f,%f v %f" />
    ]],
        2*dot_size,
        tick_pos[1], tick_pos[2], -tick_height -- mm
    ))

    f:write(string.format([[
        <text x="%f" y="%f" font-size="%f" text-anchor="end" alignment-baseline="central" font-family="Bell Centennial, Helvetica, sans-serif" transform="rotate(90)" transform-origin="%f %f" fill="green">%s</text>
    ]],
        tick_pos[1], tick_pos[2] - tick_height - 0.2, 
        1.8, -- mm, 6pt font
        tick_pos[1], tick_pos[2] - tick_height - 0.2,
        m[1]
    ))

    for d2 = 4,m[2]-1,5 do
        local day_num = d2+1
        local tick_height = 0.6
        local ta = true_anomaly(d+d2)
        local tick_pos = ecliptic(ta)
        f:write(string.format([[
            <path stroke="green" stroke-width="%f" stroke-linecap="round" d="M %f,%f v %f" />
        ]],
            2*dot_size,
            tick_pos[1], tick_pos[2], -tick_height -- mm
        ))

        if day_num == 15 then
            f:write(string.format([[
                <text x="%f" y="%f" font-size="%f" text-anchor="end" alignment-baseline="central" font-family="Bell Centennial, Helvetica, sans-serif" transform="rotate(90)" transform-origin="%f %f" fill="green">%s</text>
            ]],
                tick_pos[1], tick_pos[2] - tick_height, 
                1.4, -- mm, 4pt
                tick_pos[1], tick_pos[2] - tick_height,
                tostring(day_num)
            ))
        end
    end

    d = d + m[2]
end

--------------------
-- Mean Sun Scale --
--------------------

f:write(string.format([[
    <path d="M %f,%f h %f" stroke="green" stroke-width="%f" />
]],    
    draw_xoff, time_of_day_scale_y, draw_width,
    laser_kerf
))

-- We need to find the day of the equinox. We'll use binary search
function sun_dec(d)
    -- I don't quite know what's happening, but the equinox is defined by the mean
    -- anomaly instead of the true anomaly? idk
    local ma = true_anomaly(d,true)
    local pos = ecliptic_raw(ma)
    return pos[2]
end
-- I just happen to know this brackets the equinox that I'm after
left = 0
right = 100
assert(sun_dec(left)*sun_dec(right) <= 0, "These don't bracket the root")
iter_count = 0 -- Just to prevent infinite loops
while math.abs(sun_dec(left)) > 1e-5 do
    local m = (left+right)/2
    if sun_dec(m)*sun_dec(left) > 0 then
        left = m
    else
        right = m
    end
    iter_count = iter_count + 1
    assert(iter_count < 100, "Marco cannot write binary root search correctly")
end
equinox_day = left
print("equinox_day", equinox_day)


degrees_per_day = 360/sidereal_year

-- Find any day of the year where the Mean Sun and True Sun have the 
-- same right ascension. We do this by finding any zero of the
-- following function:
function ra_diff(d)
    local ta = true_anomaly(d)
    local pos = ecliptic_raw(ta)
    local true_sun_ra = pos[1]

    -- Right ascension is measured from the equinox, so rig our Mean
    -- Sun RA to be zero at the right time
    local mean_sun_ra = angle_clamp((d-equinox_day)*degrees_per_day)
    
    local diff = true_sun_ra-mean_sun_ra
    if diff >  180 then diff = diff - 360 end
    if diff < -180 then diff = diff + 360 end

    return diff
end

ra_at_day_0 = 360 - equinox_day*degrees_per_day

d = 0
for _,m in ipairs(months) do
    local tick_pos = vec{
        remap_x(angle_clamp(ra_at_day_0 + degrees_per_day*d)),
        time_of_day_scale_y
    }
    local tick_height = 0.8 -- mm

    f:write(string.format([[
        <path stroke="green" stroke-width="%f" stroke-linecap="round" d="M %f,%f v %f" />
    ]],
        2*dot_size,
        tick_pos[1], tick_pos[2], -tick_height -- mm
    ))

    f:write(string.format([[
        <text x="%f" y="%f" font-size="%f" text-anchor="end" alignment-baseline="central" font-family="Bell Centennial, Helvetica, sans-serif" transform="rotate(90)" transform-origin="%f %f" fill="green">%s</text>
    ]],
        tick_pos[1], tick_pos[2] - tick_height - 0.2, 
        1.8, -- mm, 6pt font
        tick_pos[1], tick_pos[2] - tick_height - 0.2,
        m[1]
    ))

    for d2 = 4,m[2]-1,5 do
        local day_num = d2+1
        local tick_height = 0.6 -- mm
        local tick_pos = vec{
            remap_x(angle_clamp(ra_at_day_0 + degrees_per_day*(d+d2))),
            time_of_day_scale_y
        }
        f:write(string.format([[
            <path stroke="green" stroke-width="%f" stroke-linecap="round" d="M %f,%f v %f" />
        ]],
            2*dot_size,
            tick_pos[1], tick_pos[2], -tick_height -- mm
        ))

        if day_num == 15 then
            f:write(string.format([[
                <text x="%f" y="%f" font-size="%f" text-anchor="end" alignment-baseline="central" font-family="Bell Centennial, Helvetica, sans-serif" transform="rotate(90)" transform-origin="%f %f" fill="green">%s</text>
            ]],
                tick_pos[1], tick_pos[2] - tick_height, 
                1.4, -- mm, 4pt
                tick_pos[1], tick_pos[2] - tick_height,
                tostring(day_num)
            ))
        end
    end

    d = d + m[2]
end


----------------------------
-- Daylight Savings Scale --
----------------------------

-- What a pain... we should really ditch DST. This is gonna be a bit less generalized.
hour_shift = -360/24 -- deg

-- afaik the rule for DST is that it starts on the second Sunday of March and ends on
-- the first Sunday of November. So the earliest it could possibly start is March 8th
-- and the latest it could possible end is November 6th. 

-- MM Mar 9 / 2024: Set the dst_start_day to just be March 1st. This makes it a lot
-- easier to read the DST scale without me having to a bunch of ugly code. P.S. today
-- is the last day of standard time; DST starts tomorrow at 2am. Go figure.
dst_first_day = months[1][2] + months[2][2]
dst_last_day  = 6
for i = 1,10 do dst_last_day = dst_last_day + months[i][2] end

-- Only draw the line in DST months
-- Measure the distance from the edge to where the first day maps to
dst_start_xpos = remap_x(angle_clamp(ra_at_day_0 + degrees_per_day*dst_first_day + hour_shift))
f:write(string.format([[
    <path d="M %f,%f h %f" stroke="green" stroke-width="%f" />
]],    
    draw_xoff, dst_scale_y, dst_start_xpos-draw_xoff,
    laser_kerf
))
-- Measure the distance from the edge to where the last day maps to
dst_end_xpos = remap_x(angle_clamp(ra_at_day_0 + degrees_per_day*dst_last_day + hour_shift))
f:write(string.format([[
    <path d="M %f,%f h %f" stroke="green" stroke-width="%f" />
]],    
    dst_end_xpos, dst_scale_y, (draw_xoff+draw_width)-dst_end_xpos,
    laser_kerf
))

-- Copy-pasted and edited... so sue me
d = 0
for _,m in ipairs(months) do
    if d >= dst_first_day and d <= dst_last_day then
        local tick_pos = vec{
            remap_x(angle_clamp(ra_at_day_0 + degrees_per_day*d + hour_shift)),
            dst_scale_y
        }
        local tick_height = 0.8 -- mm
    
        f:write(string.format([[
            <path stroke="green" stroke-width="%f" stroke-linecap="round" d="M %f,%f v %f" />
        ]],
            2*dot_size,
            tick_pos[1], tick_pos[2], tick_height -- mm
        ))
    
        f:write(string.format([[
            <text x="%f" y="%f" font-size="%f" text-anchor="start" alignment-baseline="central" font-family="Bell Centennial, Helvetica, sans-serif" transform="rotate(90)" transform-origin="%f %f" fill="green">%s</text>
        ]],
            tick_pos[1], tick_pos[2] + tick_height + 0.2, 
            1.8, -- mm, 6pt font
            tick_pos[1], tick_pos[2] + tick_height + 0.2,
            m[1]
        ))
    end
    
    for d2 = 4,m[2]-1,5 do
        if (d+d2) >= dst_first_day and (d+d2) <= dst_last_day then
            local day_num = d2+1
            local tick_height = 0.6 -- mm
            local tick_pos = vec{
                remap_x(angle_clamp(ra_at_day_0 + degrees_per_day*(d+d2) + hour_shift)),
                dst_scale_y
            }
            f:write(string.format([[
                <path stroke="green" stroke-width="%f" stroke-linecap="round" d="M %f,%f v %f" />
            ]],
                2*dot_size,
                tick_pos[1], tick_pos[2], tick_height -- mm
            ))
    
            if day_num == 15 then
                f:write(string.format([[
                    <text x="%f" y="%f" font-size="%f" text-anchor="start" alignment-baseline="central" font-family="Bell Centennial, Helvetica, sans-serif" transform="rotate(90)" transform-origin="%f %f" fill="green">%s</text>
                ]],
                    tick_pos[1], tick_pos[2] + tick_height, 
                    1.4, -- mm, 4pt
                    tick_pos[1], tick_pos[2] + tick_height,
                    tostring(day_num)
                ))
            end
        end
    end

    d = d + m[2]
end



----------------
-- Draw stars --
----------------

-- returns a reasonable radius for drawing a star
-- given its magnitude
function mag_radius(mag)
    -- Capping magnitudes
    if mag > 6.5 then mag = 6.5 end
    if mag < -1 then mag = -1 end

    -- Remap mag (exponentially) to range 1-3. This is a bit
    -- arbitrary, but basically I want the biggest stars
    -- to have a certain proportion relative to the 
    -- smallest, and I'm worried that anything "too small"
    -- won't be drawn nicely (and anyway it would be hard
    -- to see)

    mag = math.pow(10,(6.5-mag)*1/7.5) -- range 1-10
    mag = (mag-1)*2/9 + 1
    
    return dot_size*mag
end

for i,v in ipairs(tab) do
    local mag, ra, dec, name = table.unpack(v)
    if mag > 4.5 then break end
    --[[print(string.format(
            "RA=%10.6f DEC=% 10.6f mag=%-5.2g (%s)",
            v[2], v[3], v[1], v[4]
    ))]]--
    f:write(string.format(
        [[<circle cx="%f" cy="%f" r="%f" fill="black" stroke-width="0"/>]].."\n",
        remap_x(ra), remap_y(dec), mag_radius(mag)
    ))
    if false and mag < 2.2 then
        -- too bad, BSC5 doesn't have common names
        f:write(string.format(
            [[<text style="font-size:0.5" x="%f" y="%f"> %s</text>]].."\n",
            remap_x(ra), remap_y(dec), name
        ))
    end
end

------------------------
-- Close out SVG file --
------------------------

f:write"</svg>"
f:close()