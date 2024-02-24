dofile"constellation_lut.lua"

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

f:write[[
<svg viewBox="-180 -90 360 180" xmlns="http://www.w3.org/2000/svg">
<g transform="scale(1,1)">
]]

-- returns a reasonable radius for drawing a star
-- given its magnitude
function mag_radius(mag)
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
    return 0.2+math.log(mag,10)
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
        -ra + 180, -dec, mag_radius(mag)
    ))
    if false and mag < 2.2 then
        f:write(string.format(
            [[<text style="font-size:4" x="%f" y="%f"> %s</text>]].."\n",
            -ra + 180, -dec, name
        ))
    end
end

f:write"</g></svg>"

f:close()