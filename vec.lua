-- Syntactic sugar for vectors
vec_mt = {
    __add = function(a,b)
        assert(#a == #b, "Adding two uneven vectors")
        local ret = setmetatable({},getmetatable(a))
        for i,v in ipairs(a) do
            ret[i] = v + b[i]
        end
        return ret
    end,

    __sub = function(a,b)
        assert(#a == #b, "Subtracting two uneven vectors")
        local ret = setmetatable({},getmetatable(a))
        for i,v in ipairs(a) do
            ret[i] = v - b[i]
        end
        return ret
    end,

    __unm = function(a)
        local ret = setmetatable({},getmetatable(a))
        for i,v in ipairs(a) do
            ret[i] = -v
        end
        return ret
    end,

    __mul = function(s,a)
        if type(a) == "number" then
            s,a = a,s
        end

        local ret = setmetatable({},getmetatable(a))
        for i,v in ipairs(a) do
            ret[i] = s*v
        end
        return ret
    end,

    __div = function(s,a)
        if type(a) == "number" then
            s,a = a,s
        end
        assert(s ~= 0)
        return a*(1/s)
    end,

    -- Use this for dot product
    __concat = function(a,b)
        assert(#a == #b)
        local sum = 0
        for i,v in ipairs(a) do
            sum = sum + v*b[i]
        end

        return sum
    end,

    __tostring = function(v)
        local ret = "{"
        local delim = ""
        for _,val in ipairs(v) do
            ret = ret .. delim .. tostring(val) 
            delim = ","
        end

        return ret .. "}"
    end,

    norm = function(v)
        return math.sqrt(v..v)
    end
}
vec_mt.__index = vec_mt

function vec(t, ...)
    if type(t) == "number" then
        return setmetatable({t, ...}, vec_mt)
    else
        return setmetatable(t, vec_mt)
    end
end