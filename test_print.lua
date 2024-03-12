if not package.path:match"%./%?%.lua" then
    package.path = package.path .. ";./?.lua"
end
require"common"

-- Extremely dumb way for me to generate some files
-- to send to staples for a test print

a = assert(io.open"out/ankabut.svg")
l = assert(io.open"out/lawhat.svg")

tpa = assert(io.open("out/test_print_ankabut.svg", "w"))
tpl = assert(io.open("out/test_print_lawhat.svg", "w"))
-- I heard the TPL database is working again, I should
-- go take a look later...



-- Do the lawhat


ltxt = {}
for ll in l:lines() do
    if not ll:match"svg" then 
        table.insert(ltxt,ll) 
    end
end
l:close()
ltxt = table.concat(ltxt,"")

tpl:write(string.format([[
<svg viewBox="0 0 %f %f" width="%fmm" height="%fmm" transform="scale(-1,1)" xmlns="http://www.w3.org/2000/svg">
]],
        2*total_width, 4*total_height,
        2*total_width, 4*total_height
))

tpl:write[[<g id="lawhat">\n]]
tpl:write(ltxt)
tpl:write[[</g>\n]]
tpl:write(string.format([[
    <use href="#lawhat" x="%f" y="%f" />
]], total_width, 0))
tpl:write(string.format([[
    <use href="#lawhat" x="%f" y="%f" />
]], 0, total_height*2))
tpl:write(string.format([[
    <use href="#lawhat" x="%f" y="%f" />
]], total_width, total_height*2))

tpl:write"</svg>\n"
tpl:close()

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

tpa:write(string.format([[
<svg viewBox="0 0 %f %f" width="%fmm" height="%fmm" xmlns="http://www.w3.org/2000/svg">
]],
        total_width+draw_xoff+draw_width, 4*padded_height,
        total_width+draw_xoff+draw_width, 4*padded_height
))

tpa:write[[<g id="ankabut">\n]]
tpa:write(atxt)
tpa:write[[</g>\n]]
tpa:write(string.format([[
    <use href="#ankabut" x="%f" y="%f" />
]], draw_width, 0))
tpa:write(string.format([[
    <use href="#ankabut" x="%f" y="%f" />
]], 0, padded_height))
tpa:write(string.format([[
    <use href="#ankabut" x="%f" y="%f" />
]], draw_width, padded_height))
tpa:write(string.format([[
    <use href="#ankabut" x="%f" y="%f" />
]], 0, padded_height*2))
tpa:write(string.format([[
    <use href="#ankabut" x="%f" y="%f" />
]], draw_width, padded_height*2))
tpa:write(string.format([[
    <use href="#ankabut" x="%f" y="%f" />
]], 0, padded_height*3))
tpa:write(string.format([[
    <use href="#ankabut" x="%f" y="%f" />
]], draw_width, padded_height*3))

tpa:write"</svg>\n"
tpa:close()