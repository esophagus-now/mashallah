dofile"constellation_lut.lua"

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
    -- Want my_min to map to draw_yoff
    -- Want my_max to map to draw_yoff + draw_height
    return (y-my_ymin) * draw_height/my_yrange + draw_yoff
end

f = assert(io.open"IAU-CSN-fixed.txt")

tab = {}
for l in f:lines() do
    if not l:match"^#" then
        local mag = tonumber(l:sub(82,86))
        if mag then
            local RA = assert(tonumber(l:sub(105,114)))
            local DE = assert(tonumber(l:sub(116,125)))
            local name = l:sub(1,18)
            name = name:match("(.-)%s*$")
            table.insert(tab, {mag, RA, DE, name})
        end
    end
end

table.sort(tab, function(a,b) return a[1] < b[1] end)

f:close()

f = io.open("out/ankabut.svg", "wb")

f:write(string.format([[
<svg viewBox="0 0 %f %f" width="%fmm" height="%fmm" xmlns="http://www.w3.org/2000/svg">
]],
        total_width, total_height,
        total_width, total_height
))

-- returns a reasonable radius for drawing a star
-- given its magnitude
function mag_radius(mag)
    -- Capping magnitudes
    if mag > 6.5 then mag = 6.5 end
    if mag < -1 then mag = -1 end
    
    -- Linearly map mag into range 1-10. By the way,
    -- we want larger magnitudes to correspond to 
    -- smaller circles
    mag = (6.5-mag) * (9/7.5) + 1
    -- Now we take the log, which maps us into the 
    -- range 0-1
    mag = math.log(mag, 10)
    -- But we want a bigger visual difference for
    -- large magnitudes, so remap into 1-10 and 
    -- take the log again
    mag = mag*9+1
    mag = math.log(mag,10)
    -- Now we have something in the range 0-1. We want
    -- our biggest radius to be 1/150th (say) of the
    -- smallest dimension of our drawing area, and we
    -- want our smallest radius to be 1/3 (say) of that
    return (mag*0.67 + 0.33) * (1/150)*math.min(draw_width, draw_height)
end

for i,v in ipairs(tab) do
    local mag, ra, dec, name = table.unpack(v)
    if mag > 6.5 then break end
    --[[print(string.format(
            "RA=%10.6f DEC=% 10.6f mag=%-5.2g (%s)",
            v[2], v[3], v[1], v[4]
    ))]]--
    f:write(string.format(
        [[<circle cx="%f" cy="%f" r="%f" fill="black" stroke-width="0"/>]].."\n",
        remap_x(-ra + 180), remap_y(-dec), mag_radius(mag)
    ))
    if false and mag < 2.2 then
        f:write(string.format(
            [[<text style="font-size:4" x="%f" y="%f"> %s</text>]].."\n",
            remap_x(-ra + 180), remap_y(-dec), name
        ))
    end
end

f:write"</svg>"

f:close()