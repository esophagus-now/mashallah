------------------------
-- Physical constants --
------------------------
earth_ecc = 0.017 -- Eccentricity of Earth's orbit
axial_tilt = 23.44 -- degrees, US Naval Observatory 2023
latitude = 43.65  -- degrees, for Toronto
longitude = 79.38 -- degrees, for Toronto
time_zone = -5    -- hours, for Toronto
sidereal_year = 365.25636 -- 24hr days, Earth

-- Data obtained from NASA's horizons system. Units in (24hr) days
sidereal_orbital_periods = {
    {"Mercury", 87.969257 },
    {"Venus",   224.700799},
    {"Earth",   365.25636 },
    {"Mars",    686.98    },
    {"Jupiter", 4332.589  },
    {"Saturn",  10755.698 },
    {"Moon",    27.321582 }
}

------------------------
-- Drawing parameters --
------------------------
total_width  = 85.60 -- mm
total_height = 53.98 -- mm
draw_width  = total_width - 3 -- mm
draw_height = draw_width*total_height/total_width -- mm

draw_xoff = (total_width  - draw_width )/2
draw_yoff = (total_height - draw_height)/2

-- For some reason it's typical to let the x range sweep from
-- +360 to 0. I'll copy that for now until I can understand why
my_xmin = 360
my_xmax = 0
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

-- The Ponoko laser kerf is 0.2 mm. I figure this is going
-- to be similar for any laser cutter
laser_kerf = 0.2 -- mm

-- Minimum dot size on printer I'm using
printer_dpi = 300 -- DPI
dot_size = (1/printer_dpi)*25.4 -- mm


-----------------
-- Shared data --
-----------------

-- The Mean Sun scale and Sidereal Time scale have to
-- line up. Together they determine the time of day.
-- Also, we need the Daylight Savings scale to line up
time_of_day_scale_y = draw_yoff + draw_height - 9 -- mm
dst_scale_y = time_of_day_scale_y + 4 -- mm

-- For the date slide rules, it's nicer if we just have
-- some spacing on either side
rule_xoff  = draw_xoff  + 1 -- mm
rule_width = draw_width - 2 -- mm

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

planet_symbols = {}
planet_symbols.Mercury = "☿"
planet_symbols.Venus   = "♀"
planet_symbols.Earth   = "🜨"
planet_symbols.Mars    = "♂"
planet_symbols.Jupiter = "♃"
planet_symbols.Saturn  = "♄"
planet_symbols.Moon    = "☽"

----------------------
-- Helper functions --
----------------------
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

atan2  = math.atan2 or math.atan
unpack = unpack or table.unpack

-- Returns angle in degrees for the "theta" part of the spherical
-- coordinates corresponding to (x,y,z). You could reasonably call
-- this "azimuth"
-- By the way, this returns an angle from -180 to +180
function theta(x,y,z)
    return math.deg(atan2(y,x))
    --return x
end
-- Same as above but for elevation
function phi(x,y,z)
    return math.deg(atan2(z,math.sqrt((x*x)+(y*y))))
    --return z
end

-- Try to be smart about skipping discontinuities
function segs_to_svg(segs, line_width, closed, stroke)
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

        if (i == start_idx) or not connected[idx] then
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