if not package.path:match"%./%?%.lua" then
    package.path = package.path .. ";./?.lua"
end
require"common"

--------------------------------
-- SVG tag and bounding boxes --
--------------------------------

f = io.open("out/sliding_scale.svg", "wb")

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

-------------
-- Helpers --
-------------

planet_lut = {}
for _,v in ipairs(sidereal_orbital_periods) do
    planet_lut[v[1]] = v[2]
end

function year_ratio(planet)
    assert(planet_lut[planet], "Could not find planet [" .. planet .. "] in orbital periods list")

    return planet_lut[planet] / planet_lut.Earth
end

function tick_mark(x, y, h, lbl, lbr)
    f:write(string.format([[
        <path d="M %f,%f v %f" stroke-width="%f" stroke-linecap="round" stroke="black"/>
    ]],
        x, y, -h,
        laser_kerf
    ))

    -- If just a signle label provided, draw it centered above the
    -- tick line. If two labels provided, draw them on either side
    -- of the tick line
    if not lbr or #lbr == 0 then
        f:write(string.format([[
            <text x="%f" y="%f" alignment-baseline="ideographic" text-anchor="middle" font-family="Helvetica, sans-serif" font-size="1.4">%s</text>
        ]],
            x, y - h - 0.2,
            lbl
        ))
    else
        f:write(string.format([[
            <text x="%f" y="%f" text-anchor="end" font-family="Helvetica, sans-serif" font-size="1.4">%s</text>
            <text x="%f" y="%f" text-anchor="start" font-family="Helvetica, sans-serif" font-size="1.4">%s</text>
        ]],
            x - 0.2, y - h + 0.1, lbl,
            x + 0.2, y - h + 0.1, lbr
        ))
    end
end

-------------------------------------------------
-- Abrbitrary params for spacing things nicely --
-------------------------------------------------

scale_height = (draw_height-4)/7 -- mm
cur_scale_y = draw_yoff + draw_height - 4 -- mm

----------------
-- Moon orbit --
----------------

-- This is hard to explain... basically, all the other planets
-- need two steps to find their ecliptic longitude. You first
-- line up the dates, then shift that line to cross the point 
-- for the Sun. Instead, the Moon only has one step because it's
-- orbiting the Earth. So instead of putting the Moon's orbit
-- in the same ellipses diagram in the orrery, it's easier to
-- just re-use the date line we're employing with the sliding 
-- scales. That probably doesn't quite explain it, but I'll
-- include an example somewhere

-- TODO

--------------------------
-- Moon, Mercury, Venus --
--------------------------

-- For planets with an orbital period shorter than Earth's, we
-- use a layout with multiple indices

for _,planet in ipairs{"Moon", "Mercury", "Venus"} do
    local yr = year_ratio(planet)
    assert(yr < 1)

    -- Draw a base line for the tick marks
    f:write(string.format([[
        <path d="M %f,%f h %f" stroke-width="%f" stroke="black" />
    ]],
        rule_xoff, cur_scale_y,
        rule_width,
        laser_kerf
    ))

    local cur = 0

    -- Keep track of existing tick marks. When placing new ones,
    -- we try to space them out so the text is readable
    local marks = {}
    
    -- Put in all the indices
    while cur < 1 do
        tick_mark(
            cur*rule_width+rule_xoff, cur_scale_y, 2, 
            planet_symbols[planet]
        )
        table.insert(marks, cur)
        cur = cur + yr
    end
    
    -- Now draw some tick marks. This is all kind of heuristic
    -- and the intention is to get good readability

    -- We'll do all the single-year gaps up to 9, then all the
    -- ten year gaps up to 100
    local gap = 1
    while cur < 101 do
        local tick_val = math.floor(cur)
        local tick_pos = cur - tick_val

        table.insert(marks, tick_pos)
        
        tick_mark(
            rule_width*tick_pos+rule_xoff, cur_scale_y, 1,
            tostring(tick_val)
        )

        -- Figure out our desired gap
        if tick_val == 10 then gap = 10 end
        
        -- Enumerate all the valid choices for the next tick
        -- mark
        local choices = {}
        while math.floor(cur) <  tick_val+gap do cur = cur + yr end
        while math.floor(cur) == tick_val+gap do
            table.insert(choices, cur)
            cur = cur + yr
        end

        assert(#choices > 0)

        -- Select the choice with largest minimum distance to
        -- all existing marks
        local max_min_dist = 0
        local winning_pos;
        for _,c in ipairs(choices) do
            local min_dist = 1e8
            for _,m in ipairs(marks) do
                local pos = c - math.floor(c)
                local dist = pos-m
                if math.abs(dist) < math.abs(min_dist) then min_dist = dist end
            end

            if math.abs(min_dist) > math.abs(max_min_dist) then
                max_min_dist = min_dist
                winning_pos = c
            end
        end

        cur = winning_pos
        
        assert(math.floor(cur) == tick_val + gap)
    end

    cur_scale_y = cur_scale_y - scale_height
end

---------------------------
-- Mars, Jupiter, Saturn --
---------------------------

-- This is where things are more complicated. You have to remember
-- to subtract an extra year if the left index falls off the scale
-- and you end up reading under the right index. So to make this a
-- little easier to use we'll label both sides of our tick marks
-- accordingly

for _,planet in ipairs{"Mars", "Jupiter", "Saturn"} do
    local yr = year_ratio(planet)
    assert(yr > 1)

    -- Draw a base line for the tick marks
    f:write(string.format([[
        <path d="M %f,%f h %f" stroke-width="%f" stroke="black" />
    ]],
        rule_xoff, cur_scale_y,
        rule_width,
        laser_kerf
    ))

    -- Put in the indices
    tick_mark(
        0*rule_width+rule_xoff, cur_scale_y, 2, 
        planet_symbols[planet]
    )
    tick_mark(
        1*rule_width+rule_xoff, cur_scale_y, 2, 
        planet_symbols[planet]
    )

    -- Keep track of existing tick marks. When placing new ones,
    -- we try to space them out so the text is readable
    local marks = {0, 1}
    
    local cur = yr

    -- Now draw some tick marks. This is all kind of heuristic
    -- and the intention is to get good readability

    -- Here, the minimum increment is larger than 1, so we'll
    -- try to have "a few small numbers" and "a few big numbers"
    local min_gap = 1
    while cur < 101 do
        local tick_val = math.floor(cur)
        local tick_pos = cur - tick_val

        table.insert(marks, tick_pos)

        tick_mark(
            rule_width*tick_pos+rule_xoff, cur_scale_y, 1,
            tostring(tick_val), tostring(tick_val+1)
        )

        -- Figure out our desired gap
        if tick_val >= 10 then min_gap = 10 end

        while math.floor(cur) < tick_val + min_gap do
            cur = cur + yr
        end

        assert(math.floor(cur) >= tick_val + min_gap)
    end

    cur_scale_y = cur_scale_y - scale_height
end

------------------------
-- Close out SVG file --
------------------------

f:write"</svg>"
f:close()