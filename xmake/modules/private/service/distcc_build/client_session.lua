--!A cross-platform build utility based on Lua
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
-- Copyright (C) 2015-present, TBOOX Open Source Group.
--
-- @author      ruki
-- @file        client_session.lua
--

-- imports
import("core.base.pipe")
import("core.base.bytes")
import("core.base.object")
import("core.base.global")
import("core.base.option")
import("core.base.hashset")
import("core.base.scheduler")
import("private.service.client_config", {alias = "config"})
import("private.service.message")
import("private.service.stream", {alias = "socket_stream"})

-- define module
local client_session = client_session or object()

-- init client session
function client_session:init(client, session_id, token, sock)
    self._ID = session_id
    self._TOKEN = token
    self._STREAM = socket_stream(sock)
    self._CLIENT = client
end

-- get client session id
function client_session:id()
    return self._ID
end

-- get token
function client_session:token()
    return self._TOKEN
end

-- get client
function client_session:client()
    return self._CLIENT
end

-- get stream
function client_session:stream()
    return self._STREAM
end

-- run compilation job
function client_session:iorunv(program, argv, opt)
    opt = opt or {}
    local toolname = opt.toolname
    local iorunv = assert(self["_" .. toolname .. "_iorunv"], "%s: iorunv(%s) is not supported!", self, program)
    return iorunv(self, program, argv, opt)
end

-- run compilation job for gcc
function client_session:_gcc_iorunv(program, argv, opt)

    -- get flags and source file
    local flags = {}
    local cppflags = {}
    local skipped = 0
    for _, flag in ipairs(argv) do
        if flag == "-o" then
            break
        end

        -- get preprocessor flags
        table.insert(cppflags, flag)

        -- get compiler flags
        if flag == "-MMD" or flag:startswith("-I") then
            skipped = 1
        elseif flag == "-MF" or flag == "-I" or flag == "-isystem" then
            skipped = 2
        elseif flag:endswith("xcrun") then
            skipped = 4
        end
        if skipped > 0 then
            skipped = skipped - 1
        else
            table.insert(flags, flag)
        end
    end
    local objectfile = argv[#argv - 1]
    local sourcefile = argv[#argv]
    assert(objectfile and sourcefile, "%s: iorunv(%s): invalid arguments!", self, program)

    -- do preprocess
    local cppfile = objectfile:gsub("%.o$", ".p")
    local cppfiledir = path.directory(cppfile)
    if not os.isdir(cppfiledir) then
        os.mkdir(cppfiledir)
    end
    table.insert(cppflags, "-E")
    table.insert(cppflags, "-o")
    table.insert(cppflags, cppfile)
    table.insert(cppflags, sourcefile)
    os.runv(program, cppflags, opt)

    -- do compile
    local ok = false
    local errors
    local stream = self:stream()
    if stream:send_msg(message.new_compile(self:id(), opt.toolname, flags, path.filename(sourcefile), {token = self:token()})) and
        stream:send_file(cppfile, {compress = os.filesize(cppfile) > 4096}) and stream:flush() then
        if stream:recv_file(objectfile) then
            local msg = stream:recv_msg()
            if msg then
                if msg:success() then
                    ok = true
                else
                    errors = msg:errors()
                end
            end
        end
    end
    os.tryrm(cppfile)
    assert(ok, errors or "unknown errors!")
end

-- run compilation job for g++
function client_session:_gxx_iorunv(program, argv, opt)
    return self:_gcc_iorunv(program, argv, opt)
end

-- run compilation job for clang
function client_session:_clang_iorunv(program, argv, opt)
    return self:_gcc_iorunv(program, argv, opt)
end

-- run compilation job for clang++
function client_session:_clangxx_iorunv(program, argv, opt)
    return self:_gcc_iorunv(program, argv, opt)
end

-- get work directory
function client_session:workdir()
    return path.join(self:server():workdir(), "sessions", self:id())
end

function client_session:__tostring()
    return string.format("<session %s>", self:id())
end

function main(client, session_id, token, sock)
    local instance = client_session()
    instance:init(client, session_id, token, sock)
    return instance
end