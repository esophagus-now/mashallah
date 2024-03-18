-- Try not to call this script too often, we don't wanna
-- overuse the horizons API
test = io.open"ephemerides/699.txt"
if test and not arg[1] then
    print("There is already an ephemeris available. Add -f to the")
    print("command line to force a re-fetch.")
    test:close()
    os.exit(1)
end


bodies = {199, 299, 399, 499,  599,   699}
years =  { 87, 224, 364, 686, 4333, 10756} -- days, rounded down. 
-- ^^ I got this info using the horizons telnet i/f


params = {
    {"COMMAND", "@body@"}, --We'll fill this in for each body in the list
    {"OBJ_DATA", "NO"},
    {"MAKE_EPHEM", "YES"},
    {"EPHEM_TYPE", "VECTORS"},
    {"CENTER", "500@10"},
    {"START_TIME", "2024--1"},
    {"STOP_TIME", "@end_time@"}, --We'll fill this in for each body in the list
    {"VEC_TABLE", "1"},
    {"CSV_FORMAT", "YES"},
    {"OUT_UNITS", "AU-D"},
    {"STEP_SIZE", "1%20d"}
}

function get_end_time(d)
    local year = 2024
    while true do
        local year_length = (year % 4 == 0) and 366 or 365
        if d <= year_length then
            return string.format("%d--%d", year, d)
        end

        d = d - year_length
        year = year + 1

        assert(d>0)
    end
end

url_template = "https://ssd.jpl.nasa.gov/api/horizons.api?format=text"
for _,param in ipairs(params) do
    url_template = url_template .. "&" .. param[1] .. "=%27" .. param[2] .. "%27"
end

for i,body in ipairs(bodies) do
    local end_time = get_end_time(years[i])
    local url = url_template:gsub("@body@", tostring(body))
    url = url:gsub("@end_time@", end_time)

    os.execute("curl \"" .. url .. "\" -o ephemerides/" .. tostring(body) .. ".txt")
end