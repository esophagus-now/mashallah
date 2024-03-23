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
    "ephemerides/599.txt",
    "ephemerides/699.txt"
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


--------------------------------------------------
-- Shift+scale inner planets to fit on the left --
--------------------------------------------------

inner_planets = {}
inner_planets.Mercury = true
inner_planets.Venus = true
inner_planets.Earth = true
inner_planets.Mars = true

outer_planets = {}
outer_planets.Saturn = true
outer_planets.Jupiter = true
outer_planets.Earth = true

-- Leave some space at the bottom for our orbits slide rule
sun_pos_inner = vec{draw_xoff+draw_width/4,draw_yoff+draw_height/2 - 4}
sun_pos_outer = vec{draw_xoff+3*draw_width/4,draw_yoff+draw_height/2 - 4}
orbit_pt_scale_inner = 1e8 -- start big and shrink as needed
orbit_pt_scale_outer = 1e8 -- start big and shrink as needed

assert(draw_width/2 <= draw_height, "This code assumes we're limited by halfwidth")

orbits_inner = {}
orbits_outer = {}

-- Not super efficient but who cares... just iterate through all points.
-- We could do better by only checking the outermost orbit...
for planet, orbit_pts in pairs(orbits) do
    for _,pt in ipairs(orbit_pts) do
        local scale = math.abs(
            -- Leave 2.5mm of space for tick marks and text
            (draw_width/4 - 2.5)/pt[1]
        )
        if inner_planets[planet] then
            if pt[2] ~= 0 and scale < orbit_pt_scale_inner then
                orbit_pt_scale_inner = scale
            end
        end
        if outer_planets[planet] then
            if pt[2] ~= 0 and scale < orbit_pt_scale_outer then
                orbit_pt_scale_outer = scale
            end
        end
    end
end

for planet, orbit_pts in pairs(orbits) do
    if inner_planets[planet] then
        local shifted_scaled_pts = {}
        for _,pt in ipairs(orbit_pts) do
            table.insert(
                shifted_scaled_pts, 
                sun_pos_inner + orbit_pt_scale_inner*pt
            )
        end
        orbits_inner[planet] = shifted_scaled_pts
    end
    if outer_planets[planet] then
        local shifted_scaled_pts = {}
        for _,pt in ipairs(orbit_pts) do
            table.insert(
                shifted_scaled_pts, 
                sun_pos_outer + orbit_pt_scale_outer*pt
            )
        end
        orbits_outer[planet] = shifted_scaled_pts
    end
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
        dot_size
))

-- For my own sake, add an outline for the safe drawing area
f:write(string.format([[
    <rect x="%f" y="%f" width="%f" height="%f" fill="none" stroke="orange" stroke-width="%f" />
]],
    draw_xoff, draw_yoff,
    draw_width, draw_height,
    dot_size
))


-----------------------
-- Draw dots for Sun --
-----------------------

f:write(string.format([[
    <circle cx="%f" cy="%f" r="%f" />
]],
    sun_pos_outer[1],
    sun_pos_outer[2],
    laser_kerf
))

f:write(string.format([[
    <circle cx="%f" cy="%f" r="%f" />
]],
    sun_pos_inner[1],
    sun_pos_inner[2],
    laser_kerf
))
-----------------------
-- Draw orbit curves --
-----------------------

curves_inner = {}
curves_outer = {}

for planet,orbit_pts in pairs(orbits_inner) do
    io.write("Working on " .. planet .. "'s orbit")
    io.flush()
    local segs = fit_curve(
        orbit_pts,
        laser_kerf/10,
        nil, nil,
        true
    )
    print(", used ", #segs, "curve segments")
    curves_inner[planet] = segs
end

for planet,orbit_pts in pairs(orbits_outer) do
    io.write("Working on " .. planet .. "'s orbit")
    io.flush()
    local segs = fit_curve(
        orbit_pts,
        laser_kerf/10,
        nil, nil,
        true
    )
    print(", used ", #segs, "curve segments")
    curves_outer[planet] = segs
end

for planet,segs in pairs(curves_inner) do
    f:write(segs_to_svg(segs, dot_size, true, "black") .. "\n")
end

for planet,segs in pairs(curves_outer) do
    f:write(segs_to_svg(segs, dot_size, true, "black") .. "\n")
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
function tick_info(d, ignore_2024_as_leap_year, less, much_less)
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
            local ret = "'"..tostring(year%100)
            return 0.8, ret
        elseif much_less then
            return 0.6, ""
        else
            return 0.8, months[month][1]
        end
    elseif less then
        return 0,"" -- Only print months/years if tick marks turned down
    elseif d == 15 then
        -- Medium tick mark
        return 0.6, ""
    elseif d%5 == 0 then
        -- Special case: don't bother placing a tick mark for
        -- d == 30 if this is a short month
        if 
            d == 30 and (
                month == 4 or
                month == 6 or
                month == 9 or
                month == 11
            )
        then
            return 0, ""
        end
        -- Short tick mark
        return 0.4, ""
    else
        -- No tick mark
        return 0, ""
    end
end

-- Probably a better way to do this, but choose between 
-- left/middle/right for vertical/horizontal axes by
-- checking which octant the tangent lies in. For 
-- simplicity just return a string that we'll paste
-- into the SVG text attributes
function tick_text_anchor(tangent)
    local angle = angle_clamp(math.deg(atan2(tangent[2],tangent[1])) + 22.5)
    if angle <= 45 then
        return [[text-anchor="start" alignment-baseline="central"]]
    elseif angle <= 90 then
        return [[text-anchor="start" alignment-baseline="hanging"]]
    elseif angle <= 135 then
        return [[text-anchor="middle" alignment-baseline="hanging"]]
    elseif angle <= 180 then
        return [[text-anchor="end" alignment-baseline="hanging"]]
    elseif angle <= 225 then
        return [[text-anchor="end" alignment-baseline="central"]]
    elseif angle <= 270 then
        return [[text-anchor="end" alignment-baseline="ideographic"]]
    elseif angle <= 315 then
        return [[text-anchor="middle" alignment-baseline="ideographic"]]
    else
        return [[text-anchor="start" alignment-baseline="ideographic"]]
    end
end

for planet, orbit_pts in pairs(orbits_inner) do
    local is_earth = (planet == "Earth")
    local less = false
    local much_less = false
    for d,pt in ipairs(orbit_pts) do
        local tick_len, tick_str = tick_info(d, is_earth, less, much_less)
        if tick_len > 0 then
            local tangent = center_tangent(orbit_pts,d)
            -- UGLY UGLY UGLY the orbits don't return exactly to their
            -- starting location, and this is messing up the tangent
            -- calculation for the very first/last point. So add a special
            -- case for that
            if d == 1 then
                tangent = left_tangent(orbit_pts)
            elseif d == #orbit_pts then
                tangent = right_tangent(orbit_pts)
            end
            
            -- Perpendicular to tangent
            local tick_dir = vec{
                -tangent[2],
                tangent[1]
            }
            -- Make tick_dir point away from Sun
            if (tick_dir..(pt-sun_pos_inner)) < 0 then
                tick_dir = -1*tick_dir
            end
            tick_end = pt + tick_dir*tick_len
            f:write(string.format([[
                <path d="M %f,%f L %f,%f" stroke-linecap="round" stroke-width="%f" stroke="black" />
            ]],
                pt[1], pt[2],
                tick_end[1], tick_end[2],
                dot_size
            ))
            if tick_str and #tick_str > 0 then
                f:write(string.format([[
                    <text x="%f" y="%f" font-size="%f" %s font-family="Helvetica,sans-serif" fill="green">%s</text>
                ]],
                    tick_end[1], tick_end[2],
                    1.4, -- mm
                    tick_text_anchor(tick_dir),
                    tick_str
                ))
            end
        end
    end
end

for planet, orbit_pts in pairs(orbits_outer) do
    local is_earth = (planet == "Earth")
    local less = true
    local much_less = (planet == "Jupiter") or (planet == "Saturn")
    for d,pt in ipairs(orbit_pts) do
        local tick_len, tick_str = tick_info(d, is_earth, less, much_less)
        if tick_len > 0 then
            local tangent = center_tangent(orbit_pts,d)
            -- UGLY UGLY UGLY the orbits don't return exactly to their
            -- starting location, and this is messing up the tangent
            -- calculation for the very first/last point. So add a special
            -- case for that
            if d == 1 then
                tangent = left_tangent(orbit_pts)
            elseif d == #orbit_pts then
                tangent = right_tangent(orbit_pts)
            end
            -- Perpendicular to tangent
            local tick_dir = vec{
                -tangent[2],
                tangent[1]
            }
            -- Make tick_dir point away from Sun
            if (tick_dir..(pt-sun_pos_outer)) < 0 then
                tick_dir = -1*tick_dir
            end
            tick_end = pt + tick_dir*tick_len
            f:write(string.format([[
                <path d="M %f,%f L %f,%f" stroke-linecap="round" stroke-width="%f" stroke="black" />
            ]],
                pt[1], pt[2],
                tick_end[1], tick_end[2],
                dot_size
            ))
            if tick_str and #tick_str > 0 then
                f:write(string.format([[
                    <text x="%f" y="%f" font-size="%f" %s font-family="Helvetica,sans-serif" fill="green">%s</text>
                ]],
                    tick_end[1], tick_end[2],
                    1.4, -- mm
                    tick_text_anchor(tick_dir),
                    tick_str
                ))
            end
        end
    end
end

-----------------------
-- Label the planets --
-----------------------

-- TODO

-------------------------
-- Place calendar line --
-------------------------

-- Uhhh maybe we don't need to do this, right? We already have
-- a calendar line on the front side for the Mean Sun Scale.
-- Well, whatever, it's kind of nice anyway, and it's more intuitive
-- if the calendar goes left-to-right.

f:write(string.format([[
    <path d="M %f,%f h %f" stroke="green" stroke-width="%f" />
]],    
    rule_xoff, dst_scale_y, rule_width,
    laser_kerf
))

mm_per_day = rule_width/sidereal_year
-- Copy-pasted and edited... so sue me
d = 0
for i,m in ipairs(months) do
    local tick_pos = vec{
        rule_xoff + mm_per_day*d,
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

    for d2 = 4,m[2]-1,5 do
        local day_num = d2+1
        local tick_height = 0.6 -- mm
        local tick_pos = vec{
            rule_xoff + mm_per_day*(d+d2),
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

    d = d + m[2]
end


------------------------
-- Close out SVG file --
------------------------

f:write"</svg>"
f:close()