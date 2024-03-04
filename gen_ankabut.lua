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

-- For my own sake, and also because ponoko gets confused
-- without an outline, draw an outline
f:write(string.format([[
        <rect x="0" y="0" width="%f" height="%f" fill="none" stroke="pink" stroke-width="%f" />
]],
        total_width, total_height,
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


-----------------------
-- Draw the ecliptic --
-----------------------

-- Inspired by the method in Alejandro Jenkins's "The Position of
-- the Sun in the Sky".This function takes the degree angle along 
-- the ecliptic (starting from the March equinox) and returns the 
-- same RA and DEC coordinates we're using everywhere else
function ecliptic(theta)
    local gamma = -math.rad(axial_tilt)
    local stheta = math.sin(math.rad(theta))
    local ctheta = math.cos(math.rad(theta))
    return vec{
        remap_x(
            angle_clamp(math.deg(atan2(
                math.cos(gamma)*stheta,
                ctheta
            )))
        ),
        remap_y(math.deg(math.asin(-math.sin(gamma)*stheta)))
    }
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
function true_anomaly(d)
    local M = -0.0410 + 0.017202*d -- rad
    local theta_E = (
        -1.3411 + M + 0.0334*math.sin(M) + 0.0003*math.sin(2*M)
    ) -- rad
    return math.deg(theta_E)
end

months = {
    {"Ja", 31},
    {"Fe", 28},
    {"May", 31},
    {"Ap", 30},
    {"Mr", 31},
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
        <text x="%f" y="%f" font-size="%f" text-anchor="end" alignment-baseline="central" font-family="Bell Centennial, Helvetica, sans-serif" transform="rotate(90)" transform-origin="%f %f">%s</text>
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
                <text x="%f" y="%f" font-size="%f" text-anchor="end" alignment-baseline="central" font-family="Bell Centennial, Helvetica, sans-serif" transform="rotate(90)" transform-origin="%f %f">%s</text>
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


-------------------------
-- Draw constellations --
-------------------------

function add_line(x1, y1, x2, y2)
    f:write(string.format([[
        <path stroke="black" stroke-width="%f" stroke-linecap="round" d="M %f,%f L %f,%f"/>
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


-------------
-- Credits --
-------------

f:write(string.format([[
    <text font-family="Helvetica, sans-serif" font-size="1.4" x="%f" y="%f" text-anchor="middle" alignment-baseline="ideographic">Star data from Yale BSC. Ecliptic dates from a formula by Alejandro Jenkins. Constellation art from Dominic Ford.</text>
]],
    draw_xoff + draw_width/2, draw_yoff+draw_height
))

------------------------
-- Close out SVG file --
------------------------

f:write"</svg>"
f:close()