if not package.path:match"%./%?%.lua" then
    package.path = package.path .. ";./?.lua"
end
require"vec"
require"fit_curve"
require"common"
require"constellation_lut"

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

-- Inspired by the method in Alejandro Jenkins's (uhhh forgot the
-- title, something like "the position of the sun"). The RA values
-- given in IAU-CSN are relative to the March equinox, i.e. the 
-- point where the celestial equator and ecliptic meet near the
-- constellation of Aries. This function takes the angle along the
-- ecliptic (starting from the March equinox) and returns the same
-- RA and DEC coordinates we're using everywhere else
function ecliptic(theta)
    local gamma = math.rad(axial_tilt)
    local stheta = math.sin(math.rad(theta))
    local ctheta = math.cos(math.rad(theta))
    return vec{
        remap_x(
            angle_clamp(math.deg(atan2(
                math.cos(gamma)*stheta,
                ctheta
            )) + 180)
        ),
        remap_y(math.deg(math.asin(-math.sin(gamma)*stheta)))
    }
end

io.write("Working on ecliptic ")
io.flush()
segs = fit_function(
    ecliptic,
    0, 360,
    draw_tol,
    true
)
print(", used ", #segs, "curve segments")
f:write(segs_to_svg(segs, laser_kerf, true, "green") .. "\n")


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