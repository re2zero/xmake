-- main entry
function main(t)

    -- build project
    if is_host("macosx") and os.arch() ~= "arm64" then
        t:build()
    else
        return t:skip("wrong host platform")
    end
end
