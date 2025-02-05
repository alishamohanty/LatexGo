if not modules then modules = { } end modules ['font-osd'] = { -- script devanagari
    version   = 1.001,
    comment   = "companion to font-ini.mkiv",
    author    = "Kai Eigner, TAT Zetwerk / Hans Hagen, PRAGMA ADE",
    copyright = "TAT Zetwerk / PRAGMA ADE / ConTeXt Development Team",
    license   = "see context related readme files"
}


-- we need to check nbsphash (context only)

-- A few remarks:
--
-- This code is a partial rewrite of the code that deals with devanagari. The data
-- and logic is by Kai Eigner and based based on Microsoft's OpenType specifications
-- for specific scripts, but with a few improvements. More information can be found
-- at:
--
-- deva: http://www.microsoft.com/typography/OpenType%20Dev/devanagari/introO.mspx
-- dev2: http://www.microsoft.com/typography/OpenType%20Dev/devanagari/intro.mspx
--
-- Rajeesh Nambiar provided patches for the malayalam variant. Thanks to feedback
-- from the mailing list some aspects could be improved.
--
-- As I touched nearly all code, reshuffled it, optimized a lot, etc. etc. (imagine
-- how much can get messed up in over a week work) it could be that I introduced
-- bugs. There is more to gain (esp in the functions applied to a range) but I'll do
-- that when everything works as expected. Kai's original code is kept in
-- font-odk.lua as a reference so blame me (HH) for bugs. (We no longer ship that
-- file as the code below has diverted too much and in the meantime has more than
-- doubled in size.)
--
-- Interesting is that Kai managed to write this on top of the existing otf handler.
-- Only a few extensions were needed, like a few more analyzing states and dealing
-- with changed head nodes in the core scanner as that only happens here. There's a
-- lot going on here and it's only because I touched nearly all code that I got a
-- bit of a picture of what happens. For in-depth knowledge one needs to consult
-- Kai.
--
-- The rewrite mostly deals with efficiency, both in terms of speed and code. We
-- also made sure that it suits generic use as well as use in ConTeXt. I removed
-- some buglets but can as well have messed up the logic by doing this. For this we
-- keep the original around as that serves as reference. Due to the lots of
-- reshuffling glyphs quite some leaks occur(red) but once I'm satisfied with the
-- rewrite I'll weed them. I also integrated initialization etc into the regular
-- mechanisms.
--
-- In the meantime, we're down from 25.5-3.5=22 seconds to 17.7-3.5=14.2 seconds for
-- a 100 page sample (mid 2012) with both variants so it's worth the effort. Some
-- more speedup is to be expected. Due to the method chosen it will never be real
-- fast. If I ever become a power user I'll have a go at some further speed up. I
-- will rename some functions (and features) once we don't need to check the
-- original code. We now use a special subset sequence for use inside the analyzer
-- (after all we could can store this in the dataset and save redundant analysis).
--
-- By now we have yet another incremental improved version. In the end I might
-- rewrite the code.
--
-- Hans Hagen, PRAGMA-ADE, Hasselt NL

-- Todo:
--
-- Matras: according to Microsoft typography specifications "up to one of each type:
-- pre-, above-, below- or post- base", but that does not seem to be right. It could
-- become an option.
--
-- Resources:
--
-- The tables that we had here are now generated from char-def.lua or in the case of
-- generic usage loaded from luatex-basics-chr.lua. Still a couple of entries need
-- to be added to char-def.lua but finally I moved the indic specific tables there.
-- For generic usage one can create the relevant resources by running:
--
--     context luatex-basics-prepare.tex
--
-- and an overview with:
--
--     context --global s-fonts-basics.mkiv
--
-- For now we have defined: bengali, devanagari, gujarati, gurmukhi, kannada,
-- malayalam, oriya, tamil and tolugu but not all are checked. Also, some of the
-- code below might need to be adapted to the extra scripts.

local insert, imerge, copy = table.insert, table.imerge, table.copy
local next, type = next, type

local report             = logs.reporter("otf","devanagari")

fonts                    = fonts                   or { }
fonts.analyzers          = fonts.analyzers         or { }
fonts.analyzers.methods  = fonts.analyzers.methods or { node = { otf = { } } }

local otf                = fonts.handlers.otf

local handlers           = otf.handlers
local methods            = fonts.analyzers.methods

local otffeatures        = fonts.constructors.features.otf
local registerotffeature = otffeatures.register

local nuts               = nodes.nuts

local getnext            = nuts.getnext
local getprev            = nuts.getprev
local getboth            = nuts.getboth
local getid              = nuts.getid
local getchar            = nuts.getchar
local getfont            = nuts.getfont
local getsubtype         = nuts.getsubtype
local setlink            = nuts.setlink
local setnext            = nuts.setnext
local setprev            = nuts.setprev
local setchar            = nuts.setchar
local getprop            = nuts.getprop
local setprop            = nuts.setprop

local ischar             = nuts.is_char

local insert_node_after  = nuts.insert_after
local copy_node          = nuts.copy
local remove_node        = nuts.remove
local flush_list         = nuts.flush_list
local flush_node         = nuts.flush_node

local copyinjection      = nodes.injections.copy -- KE: is this necessary? HH: probably not as positioning comes later and we rawget/set

local unsetvalue         = attributes.unsetvalue

local fontdata           = fonts.hashes.identifiers

local a_state            = attributes.private('state')
local a_syllabe          = attributes.private('syllabe')

local dotted_circle      = 0x25CC
local c_nbsp             = 0x00A0
local c_zwnj             = 0x200C
local c_zwj              = 0x200D

local states             = fonts.analyzers.states -- not features

local s_rphf             = states.rphf
local s_half             = states.half
local s_pref             = states.pref
local s_blwf             = states.blwf
local s_pstf             = states.pstf

local replace_all_nbsp   = nil

replace_all_nbsp = function(head) -- delayed definition
    replace_all_nbsp = typesetters and typesetters.characters and typesetters.characters.replacenbspaces or function(head)
        return head
    end
    return replace_all_nbsp(head)
end

local processcharacters = nil

if context then
    local fontprocesses = fonts.hashes.processes
    function processcharacters(head,font)
        local processors = fontprocesses[font]
        for i=1,#processors do
            head = processors[i](head,font,0)
        end
        return head
    end
else
    function processcharacters(head,font)
        local processors = fontdata[font].shared.processes
        for i=1,#processors do
            head = processors[i](head,font,0)
        end
        return head
    end
end

-- We can assume that script are not mixed in the source but if that is the case
-- we might need to have consonants etc per script and initialize a local table
-- pointing to the right one. But not now.

local indicgroups = characters and characters.indicgroups

if not indicgroups and characters then

    local indic = {
        c = { }, -- consonant
        i = { }, -- independent vowel
        d = { }, -- dependent vowel
        m = { }, -- vowel modifier
        s = { }, -- stress tone mark
        o = { }, -- other
    }

    local indicmarks   = {
        l = { }, -- left   | pre_mark
        t = { }, -- top    | above_mark
        b = { }, -- bottom | below_mark
        r = { }, -- right  | post_mark
        s = { }, -- split  | twopart_mark
    }

    local indicclasses = {
        nukta    = { },
        halant   = { },
        ra       = { },
        anudatta = { },
    }

    local indicorders = {
        bp = { }, -- before_postscript
        ap = { }, -- after_postscript
        bs = { }, -- before_half
        as = { }, -- after_half
        bh = { }, -- before_subscript
        ah = { }, -- after_subscript
        bm = { }, -- before_main
        am = { }, -- after_main
    }

    for k, v in next, characters.data do
        local i = v.indic
        if i then
            indic[i][k] = true
            i = v.indicmark
            if i then
                if i == "s" then
                    local s = v.specials
                    indicmarks[i][k] = { s[2], s[3] }
                else
                    indicmarks[i][k] = true
                end
            end
            i = v.indicclass
            if i then
                indicclasses[i][k] = true
            end
            i = v.indicorder
            if i then
                indicorders[i][k] = true
            end
        end
    end

    indicgroups = {
        consonant         = indic.c,
        independent_vowel = indic.i,
        dependent_vowel   = indic.d,
        vowel_modifier    = indic.m,
        stress_tone_mark  = indic.s,
     -- other             = indic.o,
        pre_mark          = indicmarks.l,
        above_mark        = indicmarks.t,
        below_mark        = indicmarks.b,
        post_mark         = indicmarks.r,
        twopart_mark      = indicmarks.s,
        nukta             = indicclasses.nukta,
        halant            = indicclasses.halant,
        ra                = indicclasses.ra,
        anudatta          = indicclasses.anudatta,
        before_postscript = indicorders.bp,
        after_postscript  = indicorders.ap,
        before_half       = indicorders.bh,
        after_half        = indicorders.ah,
        before_subscript  = indicorders.bs,
        after_subscript   = indicorders.as,
        before_main       = indicorders.bm,
        after_main        = indicorders.am,
    }

    indic        = nil
    indicmarks   = nil
    indicclasses = nil
    indicorders  = nil

    characters.indicgroups = indicgroups

end

local consonant         = indicgroups.consonant
local independent_vowel = indicgroups.independent_vowel
local dependent_vowel   = indicgroups.dependent_vowel
local vowel_modifier    = indicgroups.vowel_modifier
local stress_tone_mark  = indicgroups.stress_tone_mark
local pre_mark          = indicgroups.pre_mark
local above_mark        = indicgroups.above_mark
local below_mark        = indicgroups.below_mark
local post_mark         = indicgroups.post_mark
local twopart_mark      = indicgroups.twopart_mark
local nukta             = indicgroups.nukta
local halant            = indicgroups.halant
local ra                = indicgroups.ra
local anudatta          = indicgroups.anudatta

local before_postscript = indicgroups.before_postscript
local after_postscript  = indicgroups.after_postscript
local before_half       = indicgroups.before_half
local after_half        = indicgroups.after_half
local before_subscript  = indicgroups.before_subscript
local after_subscript   = indicgroups.after_subscript
local before_main       = indicgroups.before_main
local after_main        = indicgroups.after_main

local mark_four = table.merged (
    pre_mark,
    above_mark,
    below_mark,
    post_mark
)

local mark_above_below_post = table.merged (
    above_mark,
    below_mark,
    post_mark
)

-- We use some pseudo features as we need to manipulate the nodelist based
-- on information in the font as well as already applied features. We can
-- probably replace some of the code below by injecting 'real' features
-- using the extension mechanism.

local zw_char = { -- both_joiners_true
    [c_zwnj] = true,
    [c_zwj ] = true,
}

local dflt_true = {
    dflt = true
}

local two_defaults = {
    dev2 = dflt_true,
}

local one_defaults = {
    dev2 = dflt_true,
    deva = dflt_true,
}

local false_flags = { false, false, false, false }

local sequence_reorder_matras = {
    features  = { dv01 = two_defaults },
    flags     = false_flags,
    name      = "dv01_reorder_matras",
    order     = { "dv01" },
    type      = "devanagari_reorder_matras",
    nofsteps  = 1,
    steps     = {
        {
            coverage = pre_mark,
        }
    }
}

local sequence_reorder_reph = {
    features  = { dv02 = two_defaults },
    flags     = false_flags,
    name      = "dv02_reorder_reph",
    order     = { "dv02" },
    type      = "devanagari_reorder_reph",
    nofsteps  = 1,
    steps     = {
        {
            coverage = { },
        }
    }
}

local sequence_reorder_pre_base_reordering_consonants = {
    features  = { dv03 = two_defaults },
    flags     = false_flags,
    name      = "dv03_reorder_pre_base_reordering_consonants",
    order     = { "dv03" },
    type      = "devanagari_reorder_pre_base_reordering_consonants",
    nofsteps  = 1,
    steps     = {
        {
            coverage = { },
        }
    }
}

local sequence_remove_joiners = {
    features  = { dv04 = one_defaults },
    flags     = false_flags,
    name      = "dv04_remove_joiners",
    order     = { "dv04" },
    type      = "devanagari_remove_joiners",
    nofsteps  = 1,
    steps     = {
        {
           coverage = zw_char, -- both_joiners_true
        },
    }
}

-- Looping over feature twice as efficient as looping over basic forms (some
-- 350 checks instead of 750 for one font). This is something to keep an eye on
-- as it might depends on the font. Not that it's a bottleneck.

local basic_shaping_forms =  {
 -- init = true, -- new
 -- abvs = true, -- new
    akhn = true,
    blwf = true,
 -- calt = true, -- new
    cjct = true,
    half = true,
 -- haln = true, -- new
    nukt = true,
    pref = true,
 -- pres = true, -- new
    pstf = true,
 -- psts = true, -- new
    rkrf = true,
    rphf = true,
    vatu = true,
}

local valid = {
 -- akhn = true, -- malayalam
 -- rphf = true,
 -- pref = true,
 -- half = true,
 -- blwf = true,
 -- pstf = true,
 -- pres = true, -- malayalam
 -- blws = true, -- malayalam
 -- psts = true, -- malayalam
    abvs = true,
    akhn = true,
    blwf = true,
    calt = true,
    cjct = true,
    half = true,
    haln = true,
    nukt = true,
    pref = true,
    pres = true,
    pstf = true,
    psts = true,
    rkrf = true,
    rphf = true,
    vatu = true,
    pres = true,
    abvs = true,
    blws = true,
    psts = true,
    haln = true,
    calt = true,
}

local scripts = { }

local scripts_one = { "deva", "mlym", "beng", "gujr", "guru", "knda", "orya", "taml", "telu" }
local scripts_two = { "dev2", "mlm2", "bng2", "gjr2", "gur2", "knd2", "ory2", "tml2", "tel2" }

local nofscripts = #scripts_one

for i=1,nofscripts do
    local one = scripts_one[i]
    local two = scripts_two[i]
    scripts[one] = true
    scripts[two] = true
    two_defaults[one] = dflt_true
    one_defaults[one] = dflt_true
    one_defaults[two] = dflt_true
end

local function valid_one(s) for i=1,nofscripts do if s[scripts_one[i]] then return true end end end
local function valid_two(s) for i=1,nofscripts do if s[scripts_two[i]] then return true end end end

local function initializedevanagi(tfmdata)
    local script, language = otf.scriptandlanguage(tfmdata,attr) -- todo: take fast variant
    if scripts[script] then
        local resources  = tfmdata.resources
        local devanagari = resources.devanagari
        if not devanagari then
            --
            report("adding devanagari features to font")
            --
            local gsubfeatures   = resources.features.gsub
            local sequences      = resources.sequences
            local sharedfeatures = tfmdata.shared.features
            --
            local lastmatch      = 0
            for s=1,#sequences do -- classify chars
                local features = sequences[s].features
                if features then
                    for k, v in next, features do
                        if basic_shaping_forms[k] then
                            lastmatch = s
                        end
                    end
                end
            end
            local insertindex = lastmatch + 1
            --
            gsubfeatures["dv01"] = two_defaults -- reorder matras
            gsubfeatures["dv02"] = two_defaults -- reorder reph
            gsubfeatures["dv03"] = two_defaults -- reorder pre base reordering consonants
            gsubfeatures["dv04"] = one_defaults -- remove joiners
            --
            local reorder_pre_base_reordering_consonants = copy(sequence_reorder_pre_base_reordering_consonants)
            local reorder_reph                           = copy(sequence_reorder_reph)
            local reorder_matras                         = copy(sequence_reorder_matras)
            local remove_joiners                         = copy(sequence_remove_joiners)
            --
            insert(sequences,insertindex,reorder_pre_base_reordering_consonants)
            insert(sequences,insertindex,reorder_reph)
            insert(sequences,insertindex,reorder_matras)
            insert(sequences,insertindex,remove_joiners)
            --
            local blwfcache  = { }
            local seqsubset  = { }
            local rephstep   = {
                coverage = { } -- will be adapted each work
            }
            local devanagari = {
                reph        = false,
                vattu       = false,
                blwfcache   = blwfcache,
                seqsubset   = seqsubset,
                reorderreph = rephstep,

            }
            --
            reorder_reph.steps = { rephstep }
            --
            local pre_base_reordering_consonants = { }
            reorder_pre_base_reordering_consonants.steps[1].coverage = pre_base_reordering_consonants
            --
            resources.devanagari = devanagari
            --
            for s=1,#sequences do
                local sequence = sequences[s]
                local steps    = sequence.steps
                local nofsteps = sequence.nofsteps
                local features = sequence.features
                local has_rphf = features.rphf
                local has_blwf = features.blwf
                if has_rphf and has_rphf.deva then
                    devanagari.reph = true
                elseif has_blwf and has_blwf.deva then
                    devanagari.vattu = true
                    for i=1,nofsteps do
                        local step     = steps[i]
                        local coverage = step.coverage
                        if coverage then
                            for k, v in next, coverage do
                                if not blwfcache[k] then
                                    blwfcache[k] = v
                                end
                            end
                        end
                    end
                end
                for kind, spec in next, features do
                 -- if spec.dev2 and valid[kind] then
                    if valid[kind] and valid_two(spec)then
                        for i=1,nofsteps do
                            local step     = steps[i]
                            local coverage = step.coverage
                            if coverage then
                                local reph = false
                                if kind == "rphf" then
                                    -- rphf acts on consonant + halant
                                    for k, v in next, ra do
                                        local r = coverage[k]
                                        if r then
                                            local h = false
                                            for k, v in next, halant do
                                                local h = r[k]
                                                if h then
                                                    reph = h.ligature or false
                                                    break
                                                end
                                            end
                                            if reph then
                                                break
                                            end
                                        end
                                    end
                                end
                                seqsubset[#seqsubset+1] = { kind, coverage, reph }
                            end
                        end
                    end
                    if kind == "pref" then
                        local steps    = sequence.steps
                        local nofsteps = sequence.nofsteps
                        for i=1,nofsteps do
                            local step     = steps[i]
                            local coverage = step.coverage
                            if coverage then
                                for k, v in next, halant do
                                    local h = coverage[k]
                                    if h then
                                        local found = false
                                        for k, v in next, h do
                                            found = v and v.ligature
                                            if found then
                                                pre_base_reordering_consonants[k] = found
                                                break
                                            end
                                        end
                                        if found then
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            --
            if script == "deva" then
                sharedfeatures["dv04"] = true -- dv04_remove_joiners
            elseif script == "dev2" then
                sharedfeatures["dv01"] = true -- dv01_reorder_matras
                sharedfeatures["dv02"] = true -- dv02_reorder_reph
                sharedfeatures["dv03"] = true -- dv03_reorder_pre_base_reordering_consonants
                sharedfeatures["dv04"] = true -- dv04_remove_joiners
            elseif script == "mlym" then
                sharedfeatures["pstf"] = true
            elseif script == "mlm2" then
                sharedfeatures["pstf"] = true
                sharedfeatures["pref"] = true
                sharedfeatures["dv03"] = true -- dv03_reorder_pre_base_reordering_consonants
                gsubfeatures  ["dv03"] = two_defaults -- reorder pre base reordering consonants
                insert(sequences,insertindex,sequence_reorder_pre_base_reordering_consonants)
         -- elseif script == "beng" then
         -- elseif script == "bng2" then
         -- elseif script == "gujr" then
         -- elseif script == "gjr2" then
         -- elseif script == "guru" then
         -- elseif script == "gur2" then
         -- elseif script == "knda" then
         -- elseif script == "knd2" then
            elseif script == "taml" then
                sharedfeatures["dv04"] = true -- dv04_remove_joiners
sharedfeatures["pstf"] = true
            elseif script == "tml2" then
-- sharedfeatures["pstf"] = true
-- sharedfeatures["pref"] = true
--                 sharedfeatures["dv01"] = true -- dv01_reorder_matras
--                 sharedfeatures["dv02"] = true -- dv02_reorder_reph
--                 sharedfeatures["dv03"] = true -- dv03_reorder_pre_base_reordering_consonants
--                 sharedfeatures["dv04"] = true -- dv04_remove_joiners
         -- elseif script == "telu" then
         -- elseif script == "tel2" then
            else
                report("todo: enable the right features for script %a",script)
            end
        end
    end
end

registerotffeature {
    name         = "devanagari",
    description  = "inject additional features",
    default      = true,
    initializers = {
        node     = initializedevanagi,
    },
}

local show_syntax_errors = false

local function inject_syntax_error(head,current,char)
    local signal = copy_node(current)
    copyinjection(signal,current)
    if pre_mark[char] then
        setchar(signal,dotted_circle)
    else
        setchar(current,dotted_circle)
    end
    return insert_node_after(head,current,signal)
end

-- hm, this is applied to one character:

local function initialize_one(font,attr) -- we need a proper hook into the dataset initializer

    local tfmdata        = fontdata[font]
    local datasets       = otf.dataset(tfmdata,font,attr) -- don't we know this one?
    local devanagaridata = datasets.devanagari

    if not devanagaridata then

        devanagaridata      = {
            reph      = false,
            vattu     = false,
            blwfcache = { },
        }
        datasets.devanagari = devanagaridata
        local resources     = tfmdata.resources
        local devanagari    = resources.devanagari

        for s=1,#datasets do
            local dataset = datasets[s]
            if dataset and dataset[1] then -- value
                local kind = dataset[4]
                if kind == "rphf" then
                    -- deva
                    devanagaridata.reph = true
                elseif kind == "blwf" then
                    -- deva
                    devanagaridata.vattu = true
                    -- dev2
                    devanagaridata.blwfcache = devanagari.blwfcache
                end
            end
        end

    end

    return devanagaridata.reph, devanagaridata.vattu, devanagaridata.blwfcache

end

local function reorder_one(head,start,stop,font,attr,nbspaces)

    local reph, vattu, blwfcache = initialize_one(font,attr) -- todo: a hash[font]

    local current   = start
    local n         = getnext(start)
    local base      = nil
    local firstcons = nil
    local lastcons  = nil
    local basefound = false

    if reph and ra[getchar(start)] and halant[getchar(n)] then
        -- if syllable starts with Ra + H and script has 'Reph' then exclude Reph
        -- from candidates for base consonants
        if n == stop then
            return head, stop, nbspaces
        end
        if getchar(getnext(n)) == c_zwj then
            current = start
        else
            current = getnext(n)
            setprop(start,a_state,s_rphf)
        end
    end

    if getchar(current) == c_nbsp then
        -- Stand Alone cluster
        if current == stop then
            stop = getprev(stop)
            head = remove_node(head,current)
            flush_node(current)
            return head, stop, nbspaces
        else
            nbspaces  = nbspaces + 1
            base      = current
            firstcons = current
            lastcons  = current
            current   = getnext(current)
            if current ~= stop then
                local char = getchar(current)
                if nukta[char] then
                    current = getnext(current)
                    char = getchar(current)
                end
                if char == c_zwj and current ~= stop then
                    local next = getnext(current)
                    if next ~= stop and halant[getchar(next)] then
                        current = next
                        next = getnext(current)
                        local tmp = next and getnext(next) or nil -- needs checking
                        local changestop = next == stop
                        local tempcurrent = copy_node(next)
                        copyinjection(tempcurrent,next)
                        local nextcurrent = copy_node(current)
                        copyinjection(nextcurrent,current) -- KE: necessary? HH: probably not as positioning comes later and we rawget/set
                        setlink(tempcurrent,nextcurrent)
                        setprop(tempcurrent,a_state,s_blwf)
                        tempcurrent = processcharacters(tempcurrent,font)
                        setprop(tempcurrent,a_state,unsetvalue)
                        if getchar(next) == getchar(tempcurrent) then
                            flush_list(tempcurrent)
                            if show_syntax_errors then
                                head, current = inject_syntax_error(head,current,char)
                            end
                        else
                            setchar(current,getchar(tempcurrent)) -- we assumes that the result of blwf consists of one node
                            local freenode = getnext(current)
                            setlink(current,tmp)
                            flush_node(freenode)
                            flush_list(tempcurrent)
                            if changestop then
                                stop = current
                            end
                        end
                    end
                end
            end
        end
    end

    while not basefound do
        -- find base consonant
        local char = getchar(current)
        if consonant[char] then
            setprop(current,a_state,s_half)
            if not firstcons then
                firstcons = current
            end
            lastcons = current
            if not base then
                base = current
            elseif blwfcache[char] then
                -- consonant has below-base (or post-base) form
                setprop(current,a_state,s_blwf)
            else
                base = current
            end
        end
        basefound = current == stop
        current = getnext(current)
    end

    if base ~= lastcons then
        -- if base consonant is not last one then move halant from base consonant to last one
        local np = base
        local n  = getnext(base)
        local ch = getchar(n)
        if nukta[ch] then
            np = n
            n  = getnext(n)
            ch = getchar(n)
        end
        if halant[ch] then
            if lastcons ~= stop then
                local ln = getnext(lastcons)
                if nukta[getchar(ln)] then
                    lastcons = ln
                end
            end
         -- local np = getprev(n)
            local nn = getnext(n)
            local ln = getnext(lastcons) -- what if lastcons is nn ?
            setlink(np,nn)
            setnext(lastcons,n)
            if ln then
                setprev(ln,n)
            end
            setnext(n,ln)
            setprev(n,lastcons)
            if lastcons == stop then
                stop = n
            end
        end
    end

    n = getnext(start)
    if n ~= stop and ra[getchar(start)] and halant[getchar(n)] and not zw_char[getchar(getnext(n))] then
        -- if syllable starts with Ra + H then move this combination so that it follows either:
        -- the post-base 'matra' (if any) or the base consonant
        local matra = base
        if base ~= stop then
            local next = getnext(base)
            if dependent_vowel[getchar(next)] then
                matra = next
            end
        end
        -- [sp][start][n][nn] [matra|base][?]
        -- [matra|base][start]  [n][?] [sp][nn]
        local sp = getprev(start)
        local nn = getnext(n)
        local mn = getnext(matra)
        setlink(sp,nn)
        setlink(matra,start)
        setlink(n,mn)
        if head == start then
            head = nn
        end
        start = nn
        if matra == stop then
            stop = n
        end
    end

    local current = start
    while current ~= stop do
        local next = getnext(current)
        if next ~= stop and halant[getchar(next)] and getchar(getnext(next)) == c_zwnj then
            setprop(current,a_state,unsetvalue)
        end
        current = next
    end

    if base ~= stop and getprop(base,a_state) then
        local next = getnext(base)
        if halant[getchar(next)] and not (next ~= stop and getchar(getnext(next)) == c_zwj) then
            setprop(base,a_state,unsetvalue)
        end
    end

    -- ToDo: split two- or three-part matras into their parts. Then, move the left 'matra' part to the beginning of the syllable.
    -- Not necessary for Devanagari. However it is necessay for other scripts, such as Tamil (e.g. TAMIL VOWEL SIGN O - 0BCA)

    -- classify consonants and 'matra' parts as pre-base, above-base (Reph), below-base or post-base, and group elements of the syllable (consonants and 'matras') according to this classification

    local current, allreordered, moved = start, false, { [base] = true }
    local a, b, p, bn = base, base, base, getnext(base)
    if base ~= stop and nukta[getchar(bn)] then
        a, b, p = bn, bn, bn
    end
    while not allreordered do
        -- current is always consonant
        local c = current
        local n = getnext(current)
        local l = nil -- used ?
        if c ~= stop then
            local ch = getchar(n)
            if nukta[ch] then
                c  = n
                n  = getnext(n)
                ch = getchar(n)
            end
            if c ~= stop then
                if halant[ch] then
                    c  = n
                    n  = getnext(n)
                    ch = getchar(n)
                end
                while c ~= stop and dependent_vowel[ch] do
                    c  = n
                    n  = getnext(n)
                    ch = getchar(n)
                end
                if c ~= stop then
                    if vowel_modifier[ch] then
                        c  = n
                        n  = getnext(n)
                        ch = getchar(n)
                    end
                    if c ~= stop and stress_tone_mark[ch] then
                        c = n
                        n = getnext(n)
                    end
                end
            end
        end
        local bp = getprev(firstcons)
        local cn = getnext(current)
        local last = getnext(c)
        while cn ~= last do
            -- move pre-base matras...
            if pre_mark[getchar(cn)] then
                if bp then
                    setnext(bp,cn)
                end
                local prev, next = getboth(cn)
                if next then
                    setprev(next,prev)
                end
                setnext(prev,next)
                if cn == stop then
                    stop = prev
                end
                setprev(cn,bp)
                setlink(cn,firstcons)
                if firstcons == start then
                    if head == start then
                        head = cn
                    end
                    start = cn
                end
                break
            end
            cn = getnext(cn)
        end
        allreordered = c == stop
        current = getnext(c)
    end

    if reph or vattu then
        local current, cns = start, nil
        while current ~= stop do
            local c = current
            local n = getnext(current)
            if ra[getchar(current)] and halant[getchar(n)] then
                c = n
                n = getnext(n)
                local b, bn = base, base
                while bn ~= stop  do
                    local next = getnext(bn)
                    if dependent_vowel[getchar(next)] then
                        b = next
                    end
                    bn = next
                end
                if getprop(current,a_state) == s_rphf then
                    -- position Reph (Ra + H) after post-base 'matra' (if any) since these
                    -- become marks on the 'matra', not on the base glyph
                    if b ~= current then
                        if current == start then
                            if head == start then
                                head = n
                            end
                            start = n
                        end
                        if b == stop then
                            stop = c
                        end
                        local prev = getprev(current)
                        setlink(prev,n)
                        local next = getnext(b)
                        setlink(c,next)
                        setlink(b,current)
                    end
                elseif cns and getnext(cns) ~= current then -- todo: optimize next
                    -- position below-base Ra (vattu) following the consonants on which it is placed (either the base consonant or one of the pre-base consonants)
                    local cp   = getprev(current)
                    local cnsn = getnext(cns)
                    setlink(cp,n)
                    setlink(cns,current)
                    setlink(c,cnsn)
                    if c == stop then
                        stop = cp
                        break
                    end
                    current = getprev(n)
                end
            else
                local char = getchar(current)
                if consonant[char] then
                    cns = current
                    local next = getnext(cns)
                    if halant[getchar(next)] then
                        cns = next
                    end
                elseif char == c_nbsp then
                    nbspaces   = nbspaces + 1
                    cns        = current
                    local next = getnext(cns)
                    if halant[getchar(next)] then
                        cns = next
                    end
                end
            end
            current = getnext(current)
        end
    end

    if getchar(base) == c_nbsp then
        nbspaces = nbspaces - 1
        head = remove_node(head,base)
        flush_node(base)
    end

    return head, stop, nbspaces
end

-- If a pre-base matra character had been reordered before applying basic features,
-- the glyph can be moved closer to the main consonant based on whether half-forms had been formed.
-- Actual position for the matra is defined as “after last standalone halant glyph,
-- after initial matra position and before the main consonant”.
-- If ZWJ or ZWNJ follow this halant, position is moved after it.

-- so we break out ... this is only done for the first 'word' (if we feed words we can as
-- well test for non glyph.

function handlers.devanagari_reorder_matras(head,start) -- no leak
    local current = start -- we could cache attributes here
    local startfont = getfont(start)
    local startattr = getprop(start,a_syllabe)
    while current do
        local char = ischar(current,startfont)
        local next = getnext(current)
        if char and getprop(current,a_syllabe) == startattr then
            if halant[char] and not getprop(current,a_state) then
                if next then
                    local char = ischar(next,startfont)
                    if char and zw_char[char] and getprop(next,a_syllabe) == startattr then
                        current = next
                        next    = getnext(current)
                    end
                end
                -- can be optimzied
                local startnext = getnext(start)
                head = remove_node(head,start)
                setlink(start,next)
                setlink(current,start)
             -- setlink(current,start,next) -- maybe
                start = startnext
                break
            end
        else
            break
        end
        current = next
    end
    return head, start, true
end

-- Reph’s original position is always at the beginning of the syllable, (i.e. it is
-- not reordered at the character reordering stage). However, it will be reordered
-- according to the basic-forms shaping results. Possible positions for reph,
-- depending on the script, are; after main, before post-base consonant forms, and
-- after post-base consonant forms.

-- In Devanagari reph has reordering position 'before postscript' and dev2 only
-- follows step 2, 4, and 6.

function handlers.devanagari_reorder_reph(head,start)
    local current   = getnext(start)
    local startnext = nil
    local startprev = nil
    local startfont = getfont(start)
    local startattr = getprop(start,a_syllabe)
    --
    ::step_1::
    --
    -- If reph should be positioned after post-base consonant forms, proceed to step 5.
    --
    ::step_2::
    --
    -- If the reph repositioning class is not after post-base: target position is after
    -- the first explicit halant glyph between the first post-reph consonant and last
    -- main consonant. If ZWJ or ZWNJ are following this halant, position is moved after
    -- it. If such position is found, this is the target position. Otherwise, proceed to
    -- the next step. Note: in old-implementation fonts, where classifications were
    -- fixed in shaping engine, there was no case where reph position will be found on
    -- this step.
    --
    while current do
        local char = ischar(current,startfont)
        if char and getprop(current,a_syllabe) == startattr then
            if halant[char] and not getprop(current,a_state) then
                local next = getnext(current)
                if next then
                    local nextchar = ischar(next,startfont)
                    if nextchar and zw_char[nextchar] and getprop(next,a_syllabe) == startattr then
                        current = next
                        next    = getnext(current)
                    end
                end
                startnext = getnext(start)
                head = remove_node(head,start)
                setlink(start,next)
                setlink(current,start)
             -- setlink(current,start,next) -- maybe
                start = startnext
                startattr = getprop(start,a_syllabe)
                break
            end
            current = getnext(current)
        else
            break
        end
    end
    ::step_3::
    --
    -- If reph should be repositioned after the main consonant: from the first consonant
    -- not ligated with main, or find the first consonant that is not a potential
    -- pre-base reordering Ra.
    --
    -- Kai: todo
    --
    ::step_4::
    --
    -- If reph should be positioned before post-base consonant, find first post-base
    -- classified consonant not ligated with main. If no consonant is found, the target
    -- position should be before the first matra, syllable modifier sign or vedic sign.
    --
    if not startnext then
        current = getnext(start)
        while current do
            local char = ischar(current,startfont)
            if char and getprop(current,a_syllabe) == startattr then
                if getprop(current,a_state) == s_pstf then -- post-base
                    startnext = getnext(start)
                    head = remove_node(head,start)
                    setlink(getprev(current),start)
                    setlink(start,current)
                 -- setlink(getprev(current),start,current) -- maybe
                    start = startnext
                    startattr = getprop(start,a_syllabe)
                    break
                end
                current = getnext(current)
            else
                break
            end
        end
    end
    --
    ::step_5::
    --
    -- If no consonant is found in steps 3 or 4, move reph to a position immediately
    -- before the first post-base matra, syllable modifier sign or vedic sign that has a
    -- reordering class after the intended reph position. For example, if the reordering
    -- position for reph is post-main, it will skip above-base matras that also have a
    -- post-main position.
    --
    if not startnext then
        current = getnext(start)
        local c = nil
        while current do
            local char = ischar(current,startfont)
            if char and getprop(current,a_syllabe) == startattr then
                if not c and mark_above_below_post[char] and not after_subscript[char] then
                    c = current
                end
                current = getnext(current)
            else
                break
            end
        end
        -- here we can loose the old start node: maybe best split cases
        if c then
            startnext = getnext(start)
            head = remove_node(head,start)
            setlink(getprev(c),start)
            setlink(start,c)
         -- setlink(getprev(c),start,c) -- maybe
            -- end
            start = startnext
            startattr = getprop(start,a_syllabe)
        end
    end
    --
    ::step_6::
    --
    -- Otherwise, reorder reph to the end of the syllable.
    --
    if not startnext then
        current = start
        local next = getnext(current)
        while next do
            local nextchar = ischar(next,startfont)
            if nextchar and getprop(next,a_syllabe) == startattr then
                current = next
                next = getnext(current)
            else
                break
            end
        end
        if start ~= current then
            startnext = getnext(start)
            head = remove_node(head,start)
            setlink(start,getnext(current))
            setlink(current,start)
         -- setlink(current,start,getnext(current)) -- maybe
            start = startnext
        end
    end
    --
    return head, start, true
end

-- If a pre-base reordering consonant is found, reorder it according to the following rules:
--
-- 1  Only reorder a glyph produced by substitution during application of the feature. (Note
--    that a font may shape a Ra consonant with the feature generally but block it in certain
--    contexts.)
-- 2  Try to find a target position the same way as for pre-base matra. If it is found, reorder
--    pre-base consonant glyph.
-- 3  If position is not found, reorder immediately before main consonant.

-- Here we implement a few handlers:
--
--   function(head,start,dataset,sequence,lookupmatch,rlmode,skiphash,step)
--       return head, start, done
--   end

function handlers.devanagari_reorder_pre_base_reordering_consonants(head,start)
    local current   = start
    local startnext = nil
    local startprev = nil
    local startfont = getfont(start)
    local startattr = getprop(start,a_syllabe)
    -- can be fast for loop + caching state
    while current do
        local char = ischar(current,startfont)
        if char and getprop(current,a_syllabe) == startattr then
            local next = getnext(current)
            if halant[char] and not getprop(current,a_state) then
                if next then
                    local nextchar = ischar(next,startfont)
                    if nextchar and getprop(next,a_syllabe) == startattr then
                        if nextchar == c_zwnj or nextchar == c_zwj then
                            current = next
                            next    = getnext(current)
                        end
                    end
                end
                startnext = getnext(start)
                removenode(start,start)
                setlink(start,next)
                setlink(current,start)
             -- setlink(current,start,next) -- maybe
                start = startnext
                break
            end
            current = next
        else
            break
        end
    end
    if not startnext then
        current   = getnext(start)
        startattr = getprop(start,a_syllabe)
        while current do
            local char = ischar(current,startfont)
            if char and getprop(current,a_syllabe) == startattr then
                if not consonant[char] and getprop(current,a_state) then -- main
                    startnext = getnext(start)
                    removenode(start,start)
                    setlink(getprev(current),start)
                    setlink(start,current)
                 -- setlink(getprev(current),start,current) -- maybe
                    start = startnext
                    break
                end
                current = getnext(current)
            else
                break
            end
        end
    end
    return head, start, true
end

function handlers.devanagari_remove_joiners(head,start,kind,lookupname,replacement)
    local stop = getnext(start)
    local font = getfont(start)
    local last = start
    while stop do
        local char = ischar(stop,font)
        if char and (char == c_zwnj or char == c_zwj) then
            last = stop
            stop = getnext(stop)
        else
            break
        end
    end
    local prev = getprev(start)
    if stop then
        setnext(last)
        setlink(prev,stop)
    elseif prev then
        setnext(prev)
    end
    if head == start then
        head = stop
    end
    flush_list(start)
    return head, stop, true
end

local function initialize_two(font,attr)

    local devanagari = fontdata[font].resources.devanagari

    if devanagari then
        return devanagari.seqsubset or { }, devanagari.reorderreph or { }
    else
        return { }, { }
    end

end

-- this one will be merged into the caller: it saves a call, but we will then make function
-- of the actions

local function reorder_two(head,start,stop,font,attr,nbspaces) -- maybe do a pass over (determine stop in sweep)

    local seqsubset, reorderreph = initialize_two(font,attr)

    local reph     = false -- was nil ... probably went unnoticed because never assigned
    local halfpos  = nil
    local basepos  = nil
    local subpos   = nil
    local postpos  = nil
    local locl     = { }

    for i=1,#seqsubset do

        -- this can be done more efficient, the last test and less getnext

        local subset      = seqsubset[i]
        local kind        = subset[1]
        local lookupcache = subset[2]
        if kind == "rphf" then
            reph = subset[3]
            local current = start
            local last = getnext(stop)
            while current ~= last do
                if current ~= stop then
                    local c = locl[current] or getchar(current)
                    local found = lookupcache[c]
                    if found then
                        local next = getnext(current)
                        local n = locl[next] or getchar(next)
                        if found[n] then    --above-base: rphf    Consonant + Halant
                            local afternext = next ~= stop and getnext(next)
                            if afternext and zw_char[getchar(afternext)] then -- ZWJ and ZWNJ prevent creation of reph
                                current = afternext -- getnext(next)
                            elseif current == start then
                                setprop(current,a_state,s_rphf)
                                current = next
                            else
                                current = next
                            end
                        end
                    end
                end
                current = getnext(current)
            end
        elseif kind == "pref" then
            local current = start
            local last = getnext(stop)
            while current ~= last do
                if current ~= stop then
                    local c = locl[current] or getchar(current)
                    local found = lookupcache[c]
                    if found then -- pre-base: pref	Halant + Consonant
                        local next = getnext(current)
                        local n = locl[next] or getchar(next)
                        if found[n] then
                            setprop(current,a_state,s_pref)
                            setprop(next,a_state,s_pref)
                            current = next
                        end
                    end
                end
                current = getnext(current)
            end
        elseif kind == "half" then -- half forms: half / Consonant + Halant
            local current = start
            local last = getnext(stop)
            while current ~= last do
                if current ~= stop then
                    local c = locl[current] or getchar(current)
                    local found = lookupcache[c]
                    if found then
                        local next = getnext(current)
                        local n = locl[next] or getchar(next)
                        if found[n] then
                            if next ~= stop and getchar(getnext(next)) == c_zwnj then    -- zwnj prevent creation of half
                                current = next
                            else
                                setprop(current,a_state,s_half)
                                if not halfpos then
                                    halfpos = current
                                end
                            end
                            current = getnext(current)
                        end
                    end
                end
                current = getnext(current)
            end
        elseif kind == "blwf" then -- below-base: blwf / Halant + Consonant
            local current = start
            local last = getnext(stop)
            while current ~= last do
                if current ~= stop then
                    local c = locl[current] or getchar(current)
                    local found = lookupcache[c]
                    if found then
                        local next = getnext(current)
                        local n = locl[next] or getchar(next)
                        if found[n] then
                            setprop(current,a_state,s_blwf)
                            setprop(next,a_state,s_blwf)
                            current = next
                            subpos = current
                        end
                    end
                end
                current = getnext(current)
            end
        elseif kind == "pstf" then -- post-base: pstf / Halant + Consonant
            local current = start
            local last = getnext(stop)
            while current ~= last do
                if current ~= stop then
                    local c = locl[current] or getchar(current)
                    local found = lookupcache[c]
                    if found then
                        local next = getnext(current)
                        local n = locl[next] or getchar(next)
                        if found[n] then
                            setprop(current,a_state,s_pstf)
                            setprop(next,a_state,s_pstf)
                            current = next
                            postpos = current
                        end
                    end
                end
                current = getnext(current)
            end
        end
    end

    -- this one changes per word ...

    reorderreph.coverage = { [reph] = true } -- neat

    -- end of weird

    local current, base, firstcons = start, nil, nil

    if getprop(start,a_state) == s_rphf then
        -- if syllable starts with Ra + H and script has 'Reph' then exclude Reph from candidates for base consonants
        current = getnext(getnext(start))
    end

    if current ~= getnext(stop) and getchar(current) == c_nbsp then
        -- Stand Alone cluster
        if current == stop then
            stop = getprev(stop)
            head = remove_node(head,current)
            flush_node(current)
            return head, stop, nbspaces
        else
            nbspaces = nbspaces + 1
            base     = current
            current  = getnext(current)
            if current ~= stop then
                local char = getchar(current)
                if nukta[char] then
                    current = getnext(current)
                    char = getchar(current)
                end
                if char == c_zwj then
                    local next = getnext(current)
                    if current ~= stop and next ~= stop and halant[getchar(next)] then
                        current = next
                        next = getnext(current)
                        local tmp = getnext(next)
                        local changestop = next == stop
                        setnext(next)
                        setprop(current,a_state,s_pref)
                        current = processcharacters(current,font)
                        setprop(current,a_state,s_blwf)
                        current = processcharacters(current,font)
                        setprop(current,a_state,s_pstf)
                        current = processcharacters(current,font)
                        setprop(current,a_state,unsetvalue)
                        if halant[getchar(current)] then
                            setnext(getnext(current),tmp)
                            if show_syntax_errors then
                                head, current = inject_syntax_error(head,current,char)
                            end
                        else
                            setnext(current,tmp) -- assumes that result of pref, blwf, or pstf consists of one node
                            if changestop then
                                stop = current
                            end
                        end
                    end
                end
            end
        end
    else -- not Stand Alone cluster
        local last = getnext(stop)
        while current ~= last do    -- find base consonant
            local next = getnext(current)
            if consonant[getchar(current)] then
                if not (current ~= stop and next ~= stop and halant[getchar(next)] and getchar(getnext(next)) == c_zwj) then
                    if not firstcons then
                        firstcons = current
                    end
                    -- check whether consonant has below-base or post-base form or is pre-base reordering Ra
                    local a = getprop(current,a_state)
                    if not (a == s_pref or a == s_blwf or a == s_pstf) then
                        base = current
                    end
                end
            end
            current = next
        end
        if not base then
            base = firstcons
        end
    end

    if not base then
        if getprop(start,a_state) == s_rphf then
            setprop(start,a_state,unsetvalue)
        end
        return head, stop, nbspaces
    else
        if getprop(base,a_state) then
            setprop(base,a_state,unsetvalue)
        end
        basepos = base
    end
    if not halfpos then
        halfpos = base
    end
    if not subpos then
        subpos = base
    end
    if not postpos then
        postpos = subpos or base
    end

    -- Matra characters are classified and reordered by which consonant in a conjunct they have affinity for

    local moved = { }
    local current = start
    local last = getnext(stop)
    while current ~= last do
        local char, target, cn = locl[current] or getchar(current), nil, getnext(current)
        -- not so efficient (needed for malayalam)
        local tpm = twopart_mark[char]
        if tpm then
            local extra = copy_node(current)
            copyinjection(extra,current)
            char = tpm[1]
            setchar(current,char)
            setchar(extra,tpm[2])
            head = insert_node_after(head,current,extra)
        end
        --
        if not moved[current] and dependent_vowel[char] then
            if pre_mark[char] then            -- Before first half form in the syllable
                moved[current] = true
                -- can be helper to remove one node
                local prev, next = getboth(current)
                setlink(prev,next)
                if current == stop then
                    stop = getprev(current)
                end
                if halfpos == start then
                    if head == start then
                        head = current
                    end
                    start = current
                end
                setlink(getprev(halfpos),current)
                setlink(current,halfpos)
             -- setlink(getprev(halfpos),current,halfpos) -- maybe
                halfpos = current
            elseif above_mark[char] then    -- After main consonant
                target = basepos
                if subpos == basepos then
                    subpos = current
                end
                if postpos == basepos then
                    postpos = current
                end
                basepos = current
            elseif below_mark[char] then    -- After subjoined consonants
                target = subpos
                if postpos == subpos then
                    postpos = current
                end
                subpos = current
            elseif post_mark[char] then    -- After post-form consonant
                target = postpos
                postpos = current
            end
            if mark_above_below_post[char] then
                local prev = getprev(current)
                if prev ~= target then
                    local next = getnext(current)
                    setlink(prev,next)
                    if current == stop then
                        stop = prev
                    end
                    setlink(current,getnext(target))
                    setlink(target,current)
                 -- setlink(target,current,getnext(target)) -- maybe
                end
            end
        end
        current = cn
    end

    -- Reorder marks to canonical order: Adjacent nukta and halant or nukta and vedic sign are always repositioned if necessary, so that the nukta is first.

    local current, c = start, nil
    while current ~= stop do
        local char = getchar(current)
        if halant[char] or stress_tone_mark[char] then
            if not c then
                c = current
            end
        else
            c = nil
        end
        local next = getnext(current)
        if c and nukta[getchar(next)] then
            if head == c then
                head = next
            end
            if stop == next then
                stop = current
            end
            setlink(getprev(c),next)
            local nextnext = getnext(next)
            setnext(current,nextnext)
            local nextnextnext = getnext(nextnext)
            if nextnextnext then
                setprev(nextnextnext,current)
            end
            setlink(nextnext,c)
        end
        if stop == current then break end
        current = getnext(current)
    end

    if getchar(base) == c_nbsp then
        if base == stop then
            stop = getprev(stop)
        end
        nbspaces = nbspaces - 1
        head = remove_node(head, base)
        flush_node(base)
    end

    return head, stop, nbspaces
end

-- cleaned up and optimized ... needs checking (local, check order, fixes, extra hash, etc)

local separator = { }

imerge(separator,consonant)
imerge(separator,independent_vowel)
imerge(separator,dependent_vowel)
imerge(separator,vowel_modifier)
imerge(separator,stress_tone_mark)

for k, v in next, nukta  do separator[k] = true end
for k, v in next, halant do separator[k] = true end

local function analyze_next_chars_one(c,font,variant) -- skip one dependent vowel
    -- why two variants ... the comment suggests that it's the same ruleset
    local n = getnext(c)
    if not n then
        return c
    end
    if variant == 1 then
        local v = ischar(n,font)
        if v and nukta[v] then
            n = getnext(n)
            if n then
                v = ischar(n,font)
            end
        end
        if n and v then
            local nn = getnext(n)
            if nn then
                local vv = ischar(nn,font)
                if vv then
                    local nnn = getnext(nn)
                    if nnn then
                        local vvv = ischar(nnn,font)
                        if vvv then
                            if vv == c_zwj and consonant[vvv] then
                                c = nnn
                            elseif (vv == c_zwnj or vv == c_zwj) and halant[vvv] then
                                local nnnn = getnext(nnn)
                                if nnnn then
                                    local vvvv = ischar(nnnn,font)
                                    if vvvv and consonant[vvvv] then
                                        c = nnnn
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    elseif variant == 2 then
        local v = ischar(n,font)
        if v and nukta[v] then
            c = n
        end
        n = getnext(c)
        if n then
            v = ischar(n,font)
            if v then
                local nn = getnext(n)
                if nn then
                    local vv = ischar(nn,font)
                    if vv and zw_char[v] then
                        n = nn
                        v = vv
                        nn = getnext(nn)
                        vv = nn and ischar(nn,font)
                    end
                    if vv and halant[v] and consonant[vv] then
                        c = nn
                    end
                end
            end
        end
    end
    -- c = ms_matra(c)
    local n = getnext(c)
    if not n then
        return c
    end
    local v = ischar(n,font)
    if not v then
        return c
    end
    if dependent_vowel[v] then
        c = getnext(c)
        n = getnext(c)
        if not n then
            return c
        end
        v = ischar(n,font)
        if not v then
            return c
        end
    end
    if nukta[v] then
        c = getnext(c)
        n = getnext(c)
        if not n then
            return c
        end
        v = ischar(n,font)
        if not v then
            return c
        end
    end
    if halant[v] then
        c = getnext(c)
        n = getnext(c)
        if not n then
            return c
        end
        v = ischar(n,font)
        if not v then
            return c
        end
    end
    if vowel_modifier[v] then
        c = getnext(c)
        n = getnext(c)
        if not n then
            return c
        end
        v = ischar(n,font)
        if not v then
            return c
        end
    end
    if stress_tone_mark[v] then
        c = getnext(c)
        n = getnext(c)
        if not n then
            return c
        end
        v = ischar(n,font)
        if not v then
            return c
        end
    end
    if stress_tone_mark[v] then
        return n
    else
        return c
    end
end

local function analyze_next_chars_two(c,font)
    local n = getnext(c)
    if not n then
        return c
    end
    local v = ischar(n,font)
    if v and nukta[v] then
        c = n
    end
    n = c
    while true do
        local nn = getnext(n)
        if nn then
            local vv = ischar(nn,font)
            if vv then
                if halant[vv] then
                    n = nn
                    local nnn = getnext(nn)
                    if nnn then
                        local vvv = ischar(nnn,font)
                        if vvv and zw_char[vvv] then
                            n = nnn
                        end
                    end
                elseif vv == c_zwnj or vv == c_zwj then
                 -- n = nn -- not here (?)
                    local nnn = getnext(nn)
                    if nnn then
                        local vvv = ischar(nnn,font)
                        if vvv and halant[vvv] then
                            n = nnn
                        end
                    end
                else
                    break
                end
                local nn = getnext(n)
                if nn then
                    local vv = ischar(nn,font)
                    if vv and consonant[vv] then
                        n = nn
                        local nnn = getnext(nn)
                        if nnn then
                            local vvv = ischar(nnn,font)
                            if vvv and nukta[vvv] then
                                n = nnn
                            end
                        end
                        c = n
                    else
                        break
                    end
                else
                    break
                end
            else
                break
            end
        else
            break
        end
    end
    --
    if not c then
        -- This shouldn't happen I guess.
        return
    end
    local n = getnext(c)
    if not n then
        return c
    end
    local v = ischar(n,font)
    if not v then
        return c
    end
    if anudatta[v] then
        c = n
        n = getnext(c)
        if not n then
            return c
        end
        v = ischar(n,font)
        if not v then
            return c
        end
    end
    if halant[v] then
        c = n
        n = getnext(c)
        if not n then
            return c
        end
        v = ischar(n,font)
        if not v then
            return c
        end
        if v == c_zwnj or v == c_zwj then
            c = n
            n = getnext(c)
            if not n then
                return c
            end
            v = ischar(n,font)
            if not v then
                return c
            end
        end
    else
        -- c = ms_matra(c)
        -- same as one
        if dependent_vowel[v] then
            c = n
            n = getnext(c)
            if not n then
                return c
            end
            v = ischar(n,font)
            if not v then
                return c
            end
        end
        if nukta[v] then
            c = n
            n = getnext(c)
            if not n then
                return c
            end
            v = ischar(n,font)
            if not v then
                return c
            end
        end
        if halant[v] then
            c = n
            n = getnext(c)
            if not n then
                return c
            end
            v = ischar(n,font)
            if not v then
                return c
            end
        end
    end
    -- same as one
    if vowel_modifier[v] then
        c = n
        n = getnext(c)
        if not n then
            return c
        end
        v = ischar(n,font)
        if not v then
            return c
        end
    end
    if stress_tone_mark[v] then
        c = n
        n = getnext(c)
        if not n then
            return c
        end
        v = ischar(n,font)
        if not v then
            return c
        end
    end
    if stress_tone_mark[v] then
        return n
    else
        return c
    end
end

-- It looks like these two analyzers were written independently but they share
-- a lot. Common code has been synced.

local function method_one(head,font,attr)
    local current  = head
    local start    = true
    local done     = false
    local nbspaces = 0
    while current do
        local char = ischar(current,font)
        if char then
            done = true
            local syllablestart = current
            local syllableend   = nil
            local c = current
            local n = getnext(c)
            local first = char
            if n and ra[first] then
                local second = ischar(n,font)
                if second and halant[second] then
                    local n = getnext(n)
                    if n then
                        local third = ischar(n,font)
                        if third then
                            c = n
                            first = third
                        end
                    end
                end
            end
            local standalone = first == c_nbsp
            if standalone then
                local prev = getprev(current)
                if prev then
                    local prevchar = ischar(prev,font)
                    if not prevchar then
                        -- different font or language so quite certainly a different word
                    elseif not separator[prevchar] then
                        -- something that separates words
                    else
                        standalone = false
                    end
                else
                    -- begin of paragraph or box
                end
            end
            if standalone then
                -- stand alone cluster (at the start of the word only): #[Ra+H]+NBSP+[N]+[<[<ZWJ|ZWNJ>]+H+C>]+[{M}+[N]+[H]]+[SM]+[(VD)]
                local syllableend = analyze_next_chars_one(c,font,2)
                current = getnext(syllableend)
                if syllablestart ~= syllableend then
                    head, current, nbspaces = reorder_one(head,syllablestart,syllableend,font,attr,nbspaces)
                    current = getnext(current)
                end
            else
                -- we can delay the getsubtype(n) and getfont(n) and test for say halant first
                -- as an table access is faster than two function calls (subtype and font are
                -- pseudo fields) but the code becomes messy (unless we make it a function)
                if consonant[char] then
                    -- syllable containing consonant
                    local prevc = true
                    while prevc do
                        prevc = false
                        local n = getnext(current)
                        if not n then
                            break
                        end
                        local v = ischar(n,font)
                        if not v then
                            break
                        end
                        if nukta[v] then
                            n = getnext(n)
                            if not n then
                                break
                            end
                            v = ischar(n,font)
                            if not v then
                                break
                            end
                        end
                        if halant[v] then
                            n = getnext(n)
                            if not n then
                                break
                            end
                            v = ischar(n,font)
                            if not v then
                                break
                            end
                            if v == c_zwnj or v == c_zwj then
                                n = getnext(n)
                                if not n then
                                    break
                                end
                                v = ischar(n,font)
                                if not v then
                                    break
                                end
                            end
                            if consonant[v] then
                                prevc = true
                                current = n
                            end
                        end
                    end
                    local n = getnext(current)
                    if n then
                        local v = ischar(n,font)
                        if v and nukta[v] then
                            -- nukta (not specified in Microsft Devanagari OpenType specification)
                            current = n
                            n = getnext(current)
                        end
                    end
                    syllableend = current
                    current = n
                    if current then
                        local v = ischar(current,font)
                        if not v then
                            -- skip
                        elseif halant[v] then
                            -- syllable containing consonant without vowels: {C + [Nukta] + H} + C + H
                            local n = getnext(current)
                            if n then
                                local v = ischar(n,font)
                                if v and zw_char[v] then
                                    -- code collapsed, probably needs checking with intention
                                    syllableend = n
                                    current = getnext(n)
                                else
                                    syllableend = current
                                    current = n
                                end
                            else
                                syllableend = current
                                current = n
                            end
                        else
                            -- syllable containing consonant with vowels: {C + [Nukta] + H} + C + [M] + [VM] + [SM]
                            if dependent_vowel[v] then
                                syllableend = current
                                current = getnext(current)
                                v = ischar(current,font)
                            end
                            if v and vowel_modifier[v] then
                                syllableend = current
                                current = getnext(current)
                                v = ischar(current,font)
                            end
                            if v and stress_tone_mark[v] then
                                syllableend = current
                                current = getnext(current)
                            end
                        end
                    end
                    if syllablestart ~= syllableend then
                        head, current, nbspaces = reorder_one(head,syllablestart,syllableend,font,attr,nbspaces)
                        current = getnext(current)
                    end
                elseif independent_vowel[char] then
                    -- syllable without consonants: VO + [VM] + [SM]
                    syllableend = current
                    current = getnext(current)
                    if current then
                        local v = ischar(current,font)
                        if v then
                            if vowel_modifier[v] then
                                syllableend = current
                                current = getnext(current)
                                v = ischar(current,font)
                            end
                            if v and stress_tone_mark[v] then
                                syllableend = current
                                current = getnext(current)
                            end
                        end
                    end
                else
                    if show_syntax_errors then
                        local mark = mark_four[char]
                        if mark then
                            head, current = inject_syntax_error(head,current,char)
                        end
                    end
                    current = getnext(current)
                end
            end
        else
            current = getnext(current)
        end
        start = false
    end

    if nbspaces > 0 then
        head = replace_all_nbsp(head)
    end

    return head, done
end

-- there is a good change that when we run into one with subtype < 256 that the rest is also done
-- so maybe we can omit this check (it's pretty hard to get glyphs in the stream out of the blue)

local function method_two(head,font,attr)
    local current  = head
    local start    = true
    local done     = false
    local syllabe  = 0
    local nbspaces = 0
    while current do
        local syllablestart = nil
        local syllableend   = nil
        local char = ischar(current,font)
        if char then
            done = true
            syllablestart = current
            local c = current
            local n = getnext(current)
            if n and ra[char] then
                local nextchar = ischar(n,font)
                if nextchar and halant[nextchar] then
                    local n = getnext(n)
                    if n then
                        local nextnextchar = ischar(n,font)
                        if nextnextchar then
                            c = n
                            char = nextnextchar
                        end
                    end
                end
            end
            if independent_vowel[char] then
                -- vowel-based syllable: [Ra+H]+V+[N]+[<[<ZWJ|ZWNJ>]+H+C|ZWJ+C>]+[{M}+[N]+[H]]+[SM]+[(VD)]
                current = analyze_next_chars_one(c,font,1)
                syllableend = current
            else
                local standalone = char == c_nbsp
                if standalone then
                    nbspaces = nbspaces + 1
                    local p = getprev(current)
                    if not p then
                        -- begin of paragraph or box
                    elseif ischar(p,font) then
                        -- different font or language so quite certainly a different word
                    elseif not separator[getchar(p)] then
                        -- something that separates words
                    else
                        standalone = false
                    end
                end
                if standalone then
                    -- Stand Alone cluster (at the start of the word only): #[Ra+H]+NBSP+[N]+[<[<ZWJ|ZWNJ>]+H+C>]+[{M}+[N]+[H]]+[SM]+[(VD)]
                    current = analyze_next_chars_one(c,font,2)
                    syllableend = current
                elseif consonant[getchar(current)] then
                    -- WHY current INSTEAD OF c ?

                    -- Consonant syllable: {C+[N]+<H+[<ZWNJ|ZWJ>]|<ZWNJ|ZWJ>+H>} + C+[N]+[A] + [< H+[<ZWNJ|ZWJ>] | {M}+[N]+[H]>]+[SM]+[(VD)]
                    current = analyze_next_chars_two(current,font) -- not c !
                    syllableend = current
                end
            end
        end
        if syllableend then
            syllabe = syllabe + 1
            local c = syllablestart
            local n = getnext(syllableend)
            while c ~= n do
                setprop(c,a_syllabe,syllabe)
                c = getnext(c)
            end
        end
        if syllableend and syllablestart ~= syllableend then
            head, current, nbspaces = reorder_two(head,syllablestart,syllableend,font,attr,nbspaces)
        end
        if not syllableend and show_syntax_errors then
            local char = ischar(current,font)
            if char and not getprop(current,a_state) then
                local mark = mark_four[char]
                if mark then
                    head, current = inject_syntax_error(head,current,char)
                end
            end
        end
        start = false
        current = getnext(current)
    end

    if nbspaces > 0 then
        head = replace_all_nbsp(head)
    end

    return head, done
end

for i=1,nofscripts do
    methods[scripts_one[i]] = method_one
    methods[scripts_two[i]] = method_two
end
