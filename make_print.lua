if not package.path:match"%./%?%.lua" then
    package.path = package.path .. ";./?.lua"
end
require"common"

-- Utility for making an SVG suitable for printing

function use(group_name, x, y, flip_x, group_width)
    local group_width = group_width or total_width
    local transform = ""
    if flip_x then
        transform = transform .. string.format(
            [[scale(-1,1) translate(%f,0)]],
            -group_width, group_width
        )
    end

    transform = string.format(
        "translate(%f,%f) %s",
        x, y,
        transform
    )

    return string.format([[
        <use href="#%s" transform="%s"> </use>
    ]],
        group_name, transform
    )
end


paper_width  = 8.5 * mm_per_inch
paper_height = 11  * mm_per_inch

margin = 0.5 * mm_per_inch -- Have a 1/2-inch margin to prevent problems

print_xoff   = margin
print_width  = paper_width  - 2*margin
print_yoff   = margin
print_height = paper_height - 2*margin

a = assert(io.open"out/ankabut.svg")

local cities = {}
for n=1,4 do
    if not arg[n] then arg[n] = "Toronto" end
    cities[arg[n]] = true
end

ltxt = {}
for city,_ in pairs(cities) do
    l = assert(io.open("out/lawhat_"..city..".svg"), "Could not open lawhat for [" .. city .. "]. Check your capitalization.")

    table.insert(ltxt, string.format([[<symbol id="lawhat_%s">]].."\n", city))
    for ll in l:lines() do
        if not ll:match"svg" then 
            table.insert(ltxt,ll) 
        end
    end
    l:close()

    table.insert(ltxt, "</symbol>\n")
end
ltxt = table.concat(ltxt,"")

ap = assert(io.open("out/ankabut_print.svg", "w"))
lp = assert(io.open("out/lawhat_print.svg", "w"))


-- Do the lawhat

lp:write(string.format([[
<svg viewBox="0 0 %f %f" width="%fmm" height="%fmm"" xmlns="http://www.w3.org/2000/svg">
]],
        paper_width, paper_height,
        paper_width, paper_height
))

lp:write(string.format([[
     <path d="M %f,%f v %f m %f,0 v %f" stroke-width=%f stroke="pink" fill="none"/>
]],
    print_xoff, print_yoff,
    print_height, print_width, -print_height,
    laser_kerf
))

lp:write(ltxt)

lp:write(use("lawhat_"..arg[1], print_xoff,                print_yoff+total_height, true))
lp:write(use("lawhat_"..arg[2], print_xoff+total_width+10, print_yoff+total_height, true))
lp:write(string.format([[
    <path d="M %f,%f h %f" stroke-width=%f stroke="pink" />
]],
    print_xoff, print_yoff + 2.5*total_height, print_width,
    laser_kerf
))
lp:write(use("lawhat_"..arg[3], print_xoff,                print_yoff+3.5*total_height, true))
lp:write(use("lawhat_"..arg[4], print_xoff+total_width+10, print_yoff+3.5*total_height, true))

lp:write"</svg>\n"
lp:close()

-- Do the 'ankabut

-- Add some extra spacing to make it easier to cut
-- the pieces out
padded_height = total_height + 4 -- mm

atxt = {}
for ll in a:lines() do
    if not ll:match"svg" then 
        table.insert(atxt,ll) 
    end
end
a:close()
atxt = table.concat(atxt,"")

ap:write(string.format([[
<svg viewBox="0 0 %f %f" width="%fmm" height="%fmm" xmlns="http://www.w3.org/2000/svg">
]],
        total_width+draw_xoff+draw_width, 4*padded_height,
        total_width+draw_xoff+draw_width, 4*padded_height
))

ap:write[[<g id="ankabut">\n]]
ap:write(atxt)
ap:write[[</g>\n]]
ap:write(string.format([[
    <use href="#ankabut" x="%f" y="%f" />
]], draw_width, 0))
ap:write(string.format([[
    <use href="#ankabut" x="%f" y="%f" />
]], 0, padded_height))
ap:write(string.format([[
    <use href="#ankabut" x="%f" y="%f" />
]], draw_width, padded_height))
ap:write(string.format([[
    <use href="#ankabut" x="%f" y="%f" />
]], 0, padded_height*2))
ap:write(string.format([[
    <use href="#ankabut" x="%f" y="%f" />
]], draw_width, padded_height*2))
ap:write(string.format([[
    <use href="#ankabut" x="%f" y="%f" />
]], 0, padded_height*3))
ap:write(string.format([[
    <use href="#ankabut" x="%f" y="%f" />
]], draw_width, padded_height*3))

ap:write"</svg>\n"
ap:close()