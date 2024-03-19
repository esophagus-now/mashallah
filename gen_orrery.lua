if not package.path:match"%./%?%.lua" then
    package.path = package.path .. ";./?.lua"
end
require"vec"
require"fit_curve"
require"common"

-------------------------
-- Read in ephemerides --
-------------------------

-- We'll only include planets that can be seen with the
-- naked eye. In any case, because we have to represent
-- the orbits to scale, having super huge orbits will
-- make the inner planets impossible to see.

files = {
    "ephemerides/199.txt", 
    "ephemerides/299.txt",
    "ephemerides/399.txt",
    "ephemerides/499.txt",
    --"ephemerides/599.txt",
    --"ephemerides/699.txt"
}

orbits = {}

for _,file in ipairs(files) do
    local e = assert(io.open(file,"r"))
    local state = "PREAMBLE"
    local day_num = 1
    local orbit_pts = vec{}
    local planet_name;
    for l in e:lines() do
        if state == "PREAMBLE" then
            if l:match"%$%$SOE" then
                state = "EPHEM"
            elseif l:match"Target body name" then
                planet_name = l:match": (%a*)"
                print("Reading ephemeris for "..planet_name)
            end
        elseif state == "EPHEM" then
            if l:match"%$%$EOE" then
                state = "POSTAMBLE"
            else
                local x,y = l:match(
                    ".-,"..
                    string.rep(".-,%s*([0-9E%.+-]+)",2)
                )
                x = assert(tonumber(x))
                y = assert(tonumber(y))
                table.insert(orbit_pts, vec{x,y})
            end
        else
            orbits[planet_name] = orbit_pts
            break
        end
    end
end


---------------------------------------------------
-- Shift+scale all the orbits to fit in the card --
---------------------------------------------------

sun_pos = vec{draw_xoff+draw_width/2,draw_yoff+draw_height/2}
orbit_pt_scale = 1e8 -- start big and shrink as needed

assert(draw_height <= draw_width, "This code assumes we're limited by height")

-- Not super efficient but who cares... just iterate through all points.
-- We could do better by only checking the outermost orbit...
for planet, orbit_pts in pairs(orbits) do
    for _,pt in ipairs(orbit_pts) do
        local scale = math.abs(
            (draw_height/2)/pt[2]
        )
        if pt[2] ~= 0 and scale < orbit_pt_scale then
            orbit_pt_scale = scale
        end
    end
end

for planet, orbit_pts in pairs(orbits) do
    local shifted_scaled_pts = {}
    for _,pt in ipairs(orbit_pts) do
        table.insert(
            shifted_scaled_pts, 
            sun_pos + orbit_pt_scale*pt
        )
    end
    orbits[planet] = shifted_scaled_pts
end

--------------------------------
-- SVG tag and bounding boxes --
--------------------------------

f = io.open("out/orrery.svg", "wb")

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


----------------------
-- Draw dot for Sun --
----------------------

f:write(string.format([[
    <circle cx="%f" cy="%f" r="%f" />
]],
    sun_pos[1],
    sun_pos[2],
    laser_kerf
))

-----------------------
-- Draw orbit curves --
-----------------------

curves = {}

for planet,orbit_pts in pairs(orbits) do
    io.write("Working on " .. planet .. "'s orbit")
    io.flush()
    local segs = fit_curve(
        orbit_pts,
        dot_size,
        nil, nil,
        true
    )
    print(", used ", #segs, "curve segments")
    curves[planet] = segs
end

for planet,segs in pairs(curves) do
    f:write(segs_to_svg(segs, laser_kerf, true, "black") .. "\n")
end

---------------------
-- Draw tick marks --
---------------------

-- d is a (1-indexed) number of days past Jan 1 2024.
-- For example, d=1 means Jan 1 2024 and d=60 means
-- Feb 29 2024. This returns a tick length and a string
-- label. If the tick length is zero, then we shouldn't
-- draw anything. If the string is nil, we shouldn't 
-- include any text
function tick_info(d, ignore_2024_as_leap_year)
    local year = 2024
    
    while true do
        local year_length = (year % 4 == 0) and 366 or 365
        if d <= year_length then
            break
        end

        d = d - year_length
        year = year + 1

        assert(d>0)
    end

    -- Figure out which month/day this belongs to
    local month = 1
    while true do
        -- Use our months LUT in common.lua
        local month_length = months[month][2]
        if 
            month == 2 and 
            year%4 == 0 and 
            not (year == 2024 and ignore_2024_as_leap_year)
        then
            month_length = 29 -- Leap years woooooooo
        end
        
        if d <= month_length then
            break
        end

        d = d - month_length
        month = month + 1

        assert(d>0)
        assert(month <= 12)
    end

    if d == 1 then
        -- Long tick mark
        if month == 1 then
            -- Print year and month
            return 0.8, "Ja'"..tostring(year%100)
        else
            return 0.8, months[month][1]
        end
    elseif d == 15 then
        -- Short tick mark and "15"
        return 0.6, "15"
    elseif d%5 == 0 then
        -- Short tick mark
        return 0.6, ""
    else 
        -- No tick mark
        return 0, ""
    end
end

for planet, orbit_pts in pairs(orbits) do
    local is_earth = (planet == "Earth")
    for d,pt in ipairs(orbit_pts) do
        local tick_len, tick_str = tick_info(d, is_earth)
        if tick_len > 0 then
            local tangent = center_tangent(orbit_pts,d)
            -- Perpendicular to tangent
            local tick_dir = vec{
                -tangent[2],
                tangent[1]
            }
            -- Make tick_dir point towards Sun
            if (tick_dir..(pt-sun_pos)) > 0 then
                tick_dir = -1*tick_dir
            end
            tick_end = pt + tick_dir*tick_len
            f:write(string.format([[
                <path d="M %f,%f L %f,%f" stroke-linecap="round" stroke-width="%f" stroke="black" />
            ]],
                pt[1], pt[2],
                tick_end[1], tick_end[2],
                laser_kerf
            ))
            if tick_str and #tick_str > 0 then
                f:write(string.format([[
                    <text x="%f" y="%f" font-size="%f" font-family="Helvetica,sans-serif" fill="green">%s</text>
                ]],
                    tick_end[1], tick_end[2],
                    1.4, -- mm
                    tick_str
                ))
            end
        end
    end
end


------------------------
-- Close out SVG file --
------------------------

f:write"</svg>"
f:close()