if not modules then modules = { } end modules ['luat-fmt'] = {
    version   = 1.001,
    comment   = "companion to mtxrun",
    author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
    copyright = "PRAGMA ADE / ConTeXt Development Team",
    license   = "see context related readme files"
}

local format = string.format
local concat = table.concat
local quoted = string.quoted
local luasuffixes = utilities.lua.suffixes

local report_format = logs.reporter("resolvers","formats")

local function primaryflags()
    local arguments  = environment.arguments
    local flags      = { }
    if arguments.silent then
        flags[#flags+1] = "--interaction=batchmode"
    end
 -- if arguments.jit then
 --     flags[#flags+1] = "--jiton"
 -- end
    return concat(flags," ")
end

local function secondaryflags()
    local arguments  = environment.arguments
    local trackers   = arguments.trackers
    local directives = arguments.directives
    local flags      = { }
    if trackers and trackers ~= "" then
        flags[#flags+1] = "--c:trackers=" .. quoted(trackers)
    end
    if directives and directives ~= "" then
        flags[#flags+1] = "--c:directives=" .. quoted(directives)
    end
    if arguments.silent then
        flags[#flags+1] = "--c:silent"
    end
    if arguments.errors then
        flags[#flags+1] = "--c:errors"
    end
    if arguments.jit then
        flags[#flags+1] = "--c:jiton"
    end
    if arguments.ansi then
        flags[#flags+1] = "--c:ansi"
    end
    if arguments.strip then
        flags[#flags+1] = "--c:strip"
    end
    if arguments.lmtx then
        flags[#flags+1] = "--c:lmtx"
    end
    return concat(flags," ")
end

-- The silent option is for Taco. It's a bit of a hack because we cannot yet mess
-- with directives. In fact, I could probably clean up the maker a bit by now.

local template = [[--ini %primaryflags% --lua=%luafile% %texfile% %secondaryflags% %dump% %redirect%]]

local checkers = {
    primaryflags   = "string",
    secondaryflags = "string",
    luafile        = "readable", -- "cache"
    texfile        = "readable", -- "cache"
    redirect       = "string",
    dump           = "string",
}

local runners = {
    luatex = sandbox.registerrunner {
        name     = "make luatex format",
        program  = "luatex",
        template = template,
        checkers = checkers,
        reporter = report_format,
    },
    luajittex = sandbox.registerrunner {
        name     = "make luajittex format",
        program  = "luajittex",
        template = template,
        checkers = checkers,
        reporter = report_format,
    },
}

function environment.make_format(name,arguments)
    local engine = environment.ownmain or "luatex"
    local silent = environment.arguments.silent
    local errors = environment.arguments.errors
    -- change to format path (early as we need expanded paths)
    local olddir = dir.current()
    local path = caches.getwritablepath("formats",engine) or "" -- maybe platform
    if path ~= "" then
        lfs.chdir(path)
    end
    report_format("using format path %a",dir.current())
    -- check source file
    local texsourcename = file.addsuffix(name,"mkiv")
    local fulltexsourcename = resolvers.findfile(texsourcename,"tex") or ""
    if fulltexsourcename == "" then
        texsourcename = file.addsuffix(name,"tex")
        fulltexsourcename = resolvers.findfile(texsourcename,"tex") or ""
    end
    if fulltexsourcename == "" then
        report_format("no tex source file with name %a (mkiv or tex)",name)
        lfs.chdir(olddir)
        return
    else
        report_format("using tex source file %a",fulltexsourcename)
    end
    local texsourcepath = dir.expandname(file.dirname(fulltexsourcename)) -- really needed
    -- check specification
    local specificationname = file.replacesuffix(fulltexsourcename,"lus")
    local fullspecificationname = resolvers.findfile(specificationname,"tex") or ""
    if fullspecificationname == "" then
        specificationname = file.join(texsourcepath,"context.lus")
        fullspecificationname = resolvers.findfile(specificationname,"tex") or ""
    end
    if fullspecificationname == "" then
        report_format("unknown stub specification %a",specificationname)
        lfs.chdir(olddir)
        return
    end
    local specificationpath = file.dirname(fullspecificationname)
    -- load specification
    local usedluastub = nil
    local usedlualibs = dofile(fullspecificationname)
    if type(usedlualibs) == "string" then
        usedluastub = file.join(file.dirname(fullspecificationname),usedlualibs)
    elseif type(usedlualibs) == "table" then
        report_format("using stub specification %a",fullspecificationname)
        local texbasename = file.basename(name)
        local luastubname = file.addsuffix(texbasename,luasuffixes.lua)
        local lucstubname = file.addsuffix(texbasename,luasuffixes.luc)
        -- pack libraries in stub
        report_format("creating initialization file %a",luastubname)
        utilities.merger.selfcreate(usedlualibs,specificationpath,luastubname)
        -- compile stub file (does not save that much as we don't use this stub at startup any more)
        if utilities.lua.compile(luastubname,lucstubname) and lfs.isfile(lucstubname) then
            report_format("using compiled initialization file %a",lucstubname)
            usedluastub = lucstubname
        else
            report_format("using uncompiled initialization file %a",luastubname)
            usedluastub = luastubname
        end
    else
        report_format("invalid stub specification %a",fullspecificationname)
        lfs.chdir(olddir)
        return
    end
    -- generate format
    local specification = {
        primaryflags   = primaryflags(),
        secondaryflags = secondaryflags(),
        luafile        = quoted(usedluastub),
        texfile        = quoted(fulltexsourcename),
        dump           = os.platform == "unix" and "\\\\dump" or "\\dump",
    }
    local runner = runners[engine]
    if not runner then
        report_format("format %a cannot be generated, no runner available for engine %a",name,engine)
    elseif silent then
        statistics.starttiming()
        specification.redirect = "> temp.log"
        local result  = runner(specification)
        local runtime = statistics.stoptiming()
        if result ~= 0 then
            print(format("%s silent make > fatal error when making format %q",engine,name)) -- we use a basic print
        else
            print(format("%s silent make > format %q made in %.3f seconds",engine,name,runtime)) -- we use a basic print
        end
        os.remove("temp.log")
    else
        runner(specification)
    end
    -- remove related mem files
    local pattern = file.removesuffix(file.basename(usedluastub)).."-*.mem"
 -- report_format("removing related mplib format with pattern %a", pattern)
    local mp = dir.glob(pattern)
    if mp then
        for i=1,#mp do
            local name = mp[i]
            report_format("removing related mplib format %a", file.basename(name))
            os.remove(name)
        end
    end
    lfs.chdir(olddir)
end

local template = [[%flags% --fmt=%fmtfile% --lua=%luafile% %texfile% %more%]]

local checkers = {
    flags    = "string",
    more     = "string",
    fmtfile  = "readable", -- "cache"
    luafile  = "readable", -- "cache"
    texfile  = "readable", -- "cache"
}

local runners = {
    luatex = sandbox.registerrunner {
        name     = "run luatex format",
        program  = "luatex",
        template = template,
        checkers = checkers,
        reporter = report_format,
    },
    luajittex = sandbox.registerrunner {
        name     = "run luajittex format",
        program  = "luajittex",
        template = template,
        checkers = checkers,
        reporter = report_format,
    },
}

function environment.run_format(name,data,more)
    if name and name ~= "" then
        local engine = environment.ownmain or "luatex"
        local barename = file.removesuffix(name)
        local fmtname = caches.getfirstreadablefile(file.addsuffix(barename,"fmt"),"formats",engine)
        if fmtname == "" then
            fmtname = resolvers.findfile(file.addsuffix(barename,"fmt")) or ""
        end
        fmtname = resolvers.cleanpath(fmtname)
        if fmtname == "" then
            report_format("no format with name %a",name)
        else
            local barename = file.removesuffix(name) -- expanded name
            local luaname = file.addsuffix(barename,"luc")
            if not lfs.isfile(luaname) then
                luaname = file.addsuffix(barename,"lua")
            end
            if not lfs.isfile(luaname) then
                report_format("using format name %a",fmtname)
                report_format("no luc/lua file with name %a",barename)
            else
                local runner = runners[engine]
                if not runner then
                    report_format("format %a cannot be run, no runner available for engine %a",name,engine)
                else
                    runner {
                        flags   = primaryflags(),
                        fmtfile = quoted(barename),
                        luafile = quoted(luaname),
                        texfile = quoted(data),
                        more    = more,
                    }
                end
            end
        end
    end
end
