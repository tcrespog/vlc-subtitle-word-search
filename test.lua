local lu = require('luaunit')
local script = require('../subtitle_word_search')

TestUtils = {} --class

    function TestUtils:test_encode_uri_component()
        lu.assertEquals(script.encode_uri_component("simple"), 'simple')
        lu.assertEquals(script.encode_uri_component("with space"), 'with%%20space')
        lu.assertEquals(script.encode_uri_component("underscores_and-hyphens_are_safe"), 'underscores_and-hyphens_are_safe')
        lu.assertEquals(script.encode_uri_component("dots.and.tildes~are.safe.too"), 'dots.and.tildes~are.safe.too')
        lu.assertEquals(script.encode_uri_component("unsafe:#'!&*/()?=|"), 'unsafe%%3A%%23%%27%%21%%26%%2A%%2F%%28%%29%%3F%%3D%%7C')
    end

-- class TestUtils

local runner = lu.LuaUnit.new()
runner:setOutputType("text")
os.exit( runner:runSuite() )