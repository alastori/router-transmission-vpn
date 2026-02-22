#!/usr/bin/env lua
-- oshash.lua — Compute OpenSubtitles hash for a video file
-- Algorithm: filesize + sum(first_64KB as uint64 LE) + sum(last_64KB as uint64 LE)
-- Uses split hi/lo 32-bit words to stay within Lua 5.1's double-precision range.
-- Usage: lua oshash.lua /path/to/video.mkv
-- Output: 16-character hex hash on stdout

local CHUNK = 65536  -- 64 KB
local MOD32 = 2^32

local function add64(ahi, alo, bhi, blo)
    local lo = alo + blo
    local hi = ahi + bhi
    if lo >= MOD32 then
        hi = hi + 1
        lo = lo - MOD32
    end
    return hi % MOD32, lo % MOD32
end

local function hash_chunk(f, size, hi, lo)
    local remaining = math.min(CHUNK, size)
    while remaining >= 8 do
        local data = f:read(8)
        if not data or #data < 8 then break end
        -- Read as two little-endian uint32
        local b1, b2, b3, b4, b5, b6, b7, b8 =
            data:byte(1,8)
        local wlo = b1 + b2*256 + b3*65536 + b4*16777216
        local whi = b5 + b6*256 + b7*65536 + b8*16777216
        hi, lo = add64(hi, lo, whi, wlo)
        remaining = remaining - 8
    end
    return hi, lo
end

local function oshash(path)
    local f = io.open(path, "rb")
    if not f then
        io.stderr:write("oshash: cannot open " .. path .. "\n")
        os.exit(1)
    end

    local size = f:seek("end")
    if size < CHUNK then
        f:close()
        io.stderr:write("oshash: file too small\n")
        os.exit(1)
    end

    -- Start with filesize
    local hi = math.floor(size / MOD32)
    local lo = size % MOD32

    -- Hash first 64KB
    f:seek("set", 0)
    hi, lo = hash_chunk(f, size, hi, lo)

    -- Hash last 64KB
    f:seek("set", size - CHUNK)
    hi, lo = hash_chunk(f, size, hi, lo)

    f:close()

    -- Format as 16-char hex (zero-padded)
    io.write(string.format("%08x%08x", hi, lo))
end

if not arg[1] then
    io.stderr:write("Usage: lua oshash.lua <video_file>\n")
    os.exit(1)
end

oshash(arg[1])
