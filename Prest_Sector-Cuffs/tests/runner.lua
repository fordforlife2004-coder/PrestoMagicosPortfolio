-- A tiny test runner: test(name, fn), eq(actual, expected, label), near(...), contains(text, part),
-- finish(). Shared by the fake server and the fake game.

return function()
    local passed, failed = 0, 0
    local t = {}
    function t.test(name, fn)
        local ok, err = pcall(fn)
        if ok then passed = passed + 1 else
            failed = failed + 1
            print(('FAIL %s: %s'):format(name, tostring(err)))
        end
    end
    function t.eq(actual, expected, label)
        if actual ~= expected then
            error(('%s: expected %s, got %s'):format(label or 'value', tostring(expected), tostring(actual)), 2)
        end
    end
    function t.near(actual, expected, label)
        if type(actual) ~= 'number' or math.abs(actual - expected) > 1e-6 then
            error(('%s: expected %s, got %s'):format(label or 'value', tostring(expected), tostring(actual)), 2)
        end
    end
    function t.contains(text, part, label)
        if type(text) ~= 'string' or not text:find(part, 1, true) then
            error(('%s: expected "%s" in "%s"'):format(label or 'text', part, tostring(text)), 2)
        end
    end
    function t.finish()
        print(('%d passed, %d failed'):format(passed, failed))
        if failed > 0 then error(('%d test(s) failed'):format(failed)) end
    end
    return t
end
