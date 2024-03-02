-- Transcribed manually (because I guess that's
-- what I'm doing) from table 11 of the IAU
-- style manual. Obtained from:
-- https://www.iau.org/static/publications/stylemanual1989.pdf

constellation_lut = {
    ["And"] = "andromeda",
    Ant = "Antlia",
    Aps = "Apus",
    Aqr = "Aquarius",
    Aql = "Aquila",
    Ara = "Ara",
    Arg = "Argo",
    Ari = "Aries",
    Aur = "Auriga",
    Boo = "Bootes",
    Cae = "Caelum",
    Cam = "Camelopardalis",
    Cnc = "Cancer",
    CVn = "Canes Venatici",
    CMa = "Canis Major",
    CMi = "Canis Minor",
    Cap = "Capricorn",
    Car = "Carina",
    Cas = "Cassiopeia",
    Cen = "Centaurus",
    Cep = "Cepheus",
    Cet = "Cetus",
    Cha = "Chamaeleon",
    Cir = "Circinus",
    Col = "Columba",
    Com = "Coma Berenices",
    CrA = "Corona Australis",
    CrB = "Corona Borealis",
    Crv = "Corvus",
    Crt = "Crater",
    Cru = "Crux",
    Cyg = "Cygnus",
    Del = "Delphinus",
    Dor = "Dorado",
    Dra = "Draco",
    Equ = "Equuleus",
    Eri = "Eridanus",
    ["For"] = "Fornax",
    Gem = "Gemini",
    Gru = "Grus",
    Her = "Hercules",
    Hor = "Horologium",
    Hya = "Hydra",
    Hyi = "Hydrus",
    Ind = "Indus",
    Lac = "Lacerta",
    Leo = "Leo",
    LMi = "Leo Minor",
    Lep = "Lepus",
    Lib = "Libra",
    Lup = "Lupus",
    Lyn = "Lynx",
    Lyr = "Lyra",
    Men = "Mensa",
    Mic = "Microscopium",
    Mon = "Monoceros",
    Mus = "Musca",
    Nor = "Norma",
    Oct = "Octans",
    Oph = "Ophiuchus",
    Ori = "Orion",
    Pav = "Pavo",
    Peg = "Pegasus",
    Per = "Perseus",
    Phe = "Phoenix",
    Pic = "Pictor",
    Psc = "Pisces",
    PsA = "Pscis Australis",
    Pip = "Puppis",
    Pyx = "Pyxis",
    Ret = "Reticulum",
    Sge = "Sagitta",
    Sgr = "Sagittarius",
    Sco = "Scorpius",
    Sct = "Scutum",
    Ser = "Serpens",
    Sex = "Sextans", -- tee hee
    Tau = "Taurus",
    Tel = "Telescopium",
    Tri = "Triangulum",
    TrA = "Triangulum",
    Tuc = "Tucana",
    UMa = "Ursa Major",
    UMi = "Ursa Minor",
    Vel = "Vela",
    Vir = "Virgo",
    Vol = "Volans",
    Vul = "Vulpecula"
}

-- Go ahead and make a bunch of other lookups
-- for convenience
for k,v in pairs(constellation_lut) do
    constellation_lut[k:lower()] = v
    constellation_lut[v] = k
end