-- Extremely dumb way for me to test out sliding the two 
-- drawings over each other. Right now I'm doing this by
-- opening the SVG and using the browser's dev tools to
-- edit the transform of the Lawhat group

a = assert(io.open"out/ankabut.svg")
l = assert(io.open"out/lawhat.svg")

b = assert(io.open("out/both.svg", "w"))

ltxt = {}
for ll in l:lines() do
    if not ll:match"svg" then 
        table.insert(ltxt,ll) 
    end
end

l:close()

for al in a:lines() do
    b:write(al)
    if al:match"<svg" then
        b:write"<g>\n"
        b:write(table.concat(ltxt,""))
        b:write"</g>\n"
    end
end

a:close()

b:close()