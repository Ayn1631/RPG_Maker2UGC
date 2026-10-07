-- Pure Lua 5.3 SHA-256 implementation for deterministic build identities.
return function()
    -- SHA-256 arithmetic is defined on unsigned 32-bit words; Lua integers are wider.
    local mask = 0xffffffff
    -- The standard per-round constants, applied in the algorithm's fixed order.
    local constants = {
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
    }
    -- Rotate within one 32-bit word, discarding bits shifted beyond its boundary.
    local function rotate(x, n) return ((x >> n) | (x << (32 - n))) & mask end
    -- Serialize one word in SHA-256's big-endian byte order.
    local function word(x) return string.char((x >> 24) & 255, (x >> 16) & 255, (x >> 8) & 255, x & 255) end
    -- Hash the exact input bytes and return the conventional 64-character lowercase digest.
    local function hex(bytes)
        assert(type(bytes) == "string", "SHA-256 input must be a string")
        local length = #bytes
        local padding = (55 - length) % 64
        local data = bytes .. "\128" .. string.rep("\0", padding) .. word((length >> 29) & mask) .. word((length << 3) & mask)
        local h = { 0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19 }
        for start = 1, #data, 64 do
            local w = {}
            for i = 0, 15 do
                local a,b,c,d = data:byte(start + i * 4, start + i * 4 + 3)
                w[i] = (a << 24) | (b << 16) | (c << 8) | d
            end
            for i = 16, 63 do
                local x,y = w[i-15],w[i-2]
                local s0 = rotate(x,7) ~ rotate(x,18) ~ (x >> 3)
                local s1 = rotate(y,17) ~ rotate(y,19) ~ (y >> 10)
                w[i] = (w[i-16] + s0 + w[i-7] + s1) & mask
            end
            local a,b,c,d,e,f,g,hh = table.unpack(h)
            for i = 0, 63 do
                local s1 = rotate(e,6) ~ rotate(e,11) ~ rotate(e,25)
                local choose = (e & f) ~ ((~e) & g)
                local t1 = (hh + s1 + choose + constants[i+1] + w[i]) & mask
                local s0 = rotate(a,2) ~ rotate(a,13) ~ rotate(a,22)
                local majority = (a & b) ~ (a & c) ~ (b & c)
                local t2 = (s0 + majority) & mask
                hh,g,f,e,d,c,b,a = g,f,e,(d+t1)&mask,c,b,a,(t1+t2)&mask
            end
            local values = {a,b,c,d,e,f,g,hh}
            for i = 1, 8 do h[i] = (h[i] + values[i]) & mask end
        end
        local out = {}
        for i = 1, 8 do out[i] = string.format("%08x", h[i]) end
        return table.concat(out)
    end
    return { hex = hex }
end
