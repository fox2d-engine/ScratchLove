-- Pen Renderer Performance and Function Test

-- Set up package path to find project modules
local testPath = debug.getinfo(1, "S").source:match("@(.*/)")
local projectRoot = testPath:gsub("tests/unit/$", "")
package.path = projectRoot .. "?.lua;" .. projectRoot .. "?/init.lua;" .. package.path

-- Set up mock environment
local MockLove = require("tests.mocks.love_mock")
MockLove.install()

-- Import testing framework
local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local PenRenderer = require("pen.pen_renderer")
local Global = require("global")

describe("PenRenderer Core Behaviour", function()
    it("should initialize with an empty path list", function()
        local renderer = PenRenderer:new()
        expect(renderer.pathNodes).to.be.a("table")
        expect(#renderer.pathNodes).to.equal(0)
    end)

    it("should add line nodes correctly", function()
        local renderer = PenRenderer:new()
        renderer:queueLine(0, 0, 10, 10, 5, 50, 100, 100, 0)

        expect(#renderer.pathNodes).to.equal(1)
        local node = renderer.pathNodes[1]
        expect(node.nodeType).to.equal("line")
        expect(node.x).to.equal(0)
        expect(node.y).to.equal(0)
        expect(node.endX).to.equal(10)
        expect(node.endY).to.equal(10)
        expect(node.size).to.equal(5)
    end)

    it("should add point nodes correctly", function()
        local renderer = PenRenderer:new()
        renderer:queuePoint(5, 5, 3, 100, 50, 80, 10)

        expect(#renderer.pathNodes).to.equal(1)
        local node = renderer.pathNodes[1]
        expect(node.nodeType).to.equal("point")
        expect(node.x).to.equal(5.5) -- 5 + 0.5 pixel alignment for size 3
        expect(node.y).to.equal(5.5) -- 5 + 0.5 pixel alignment for size 3
        expect(node.size).to.equal(3)
    end)

    it("should handle clear operations", function()
        local renderer = PenRenderer:new()
        -- Add some nodes first
        renderer:queueLine(0, 0, 10, 10, 5, 50, 100, 100, 0)
        renderer:queuePoint(5, 5, 3, 100, 50, 80, 10)
        expect(#renderer.pathNodes).to.equal(2)

        -- Clear should reset nodes
        renderer:queueClear()
        expect(#renderer.pathNodes).to.equal(1)
        expect(renderer.pathNodes[1].nodeType).to.equal("clear")
    end)

    it("should skip zero-length lines", function()
        local renderer = PenRenderer:new()
        renderer:queueLine(5, 5, 5, 5, 3, 50, 100, 100, 0)
        expect(#renderer.pathNodes).to.equal(0)
    end)

    it("should convert Scratch colors to RGBA correctly", function()
        local renderer = PenRenderer:new()
        local r, g, b, a = renderer:scratchColorToRGBA(0, 100, 100, 0) -- Red
        expect(math.abs(r - 1.0) < 0.01).to.be.truthy()
        expect(math.abs(g - 0.0) < 0.01).to.be.truthy()
        expect(math.abs(b - 0.0) < 0.01).to.be.truthy()
        expect(a).to.equal(1.0)

        local r2, g2, b2, a2 = renderer:scratchColorToRGBA(50, 100, 100, 50) -- Cyan (hue 50 in 0-100 range), 50% transparent
        expect(math.abs(r2 - 0.0) < 0.01).to.be.truthy()
        expect(math.abs(g2 - 1.0) < 0.01).to.be.truthy()
        expect(math.abs(b2 - 1.0) < 0.01).to.be.truthy()
        expect(a2).to.equal(0.5)
    end)

    it("should coordinate convert correctly", function()
        local renderer = PenRenderer:new()
        -- Coordinates are scaled by renderQuality (auto-detected from DPI)
        local canvasX, canvasY = renderer:scratchToCanvas(0, 0) -- Stage center
        expect(canvasX).to.equal(Global.STAGE_HALF_WIDTH * renderer.renderQuality)
        expect(canvasY).to.equal(Global.STAGE_HALF_HEIGHT * renderer.renderQuality)

        local canvasX2, canvasY2 = renderer:scratchToCanvas(-240, 180) -- Top-left corner in Scratch coords
        expect(canvasX2).to.equal(0)     -- (-240 + 240) * renderQuality = 0
        expect(canvasY2).to.equal(0)     -- (180 - 180) * renderQuality = 0
    end)

    it("should flush queued nodes to the canvas", function()
        local renderer = PenRenderer:new()
        renderer:queueLine(0, 0, 50, 50, 10, 50, 100, 100, 0)
        renderer:flush()

        expect(#renderer.pathNodes).to.equal(0)
    end)
end)

-- Performance benchmark (optional)
describe("PenRenderer Performance Tests", function()

    it("should handle large numbers of nodes efficiently", function()
        local renderer = PenRenderer:new()
        local startTime = love.timer.getTime()

        -- Add 1000 line segments
        for i = 1, 1000 do
            local x1, y1 = math.random(-240, 240), math.random(-180, 180)
            local x2, y2 = math.random(-240, 240), math.random(-180, 180)
            renderer:queueLine(x1, y1, x2, y2, math.random(1, 10),
                math.random(0, 200), math.random(0, 100), math.random(0, 100), 0)
        end

        local addTime = love.timer.getTime() - startTime
        expect(#renderer.pathNodes).to.equal(1000)

        -- Render should be reasonably fast
        local renderStart = love.timer.getTime()
        renderer:flush()
        local renderTime = love.timer.getTime() - renderStart

        print(string.format("Performance: Added 1000 nodes in %.2fms, rendered in %.2fms",
            addTime * 1000, renderTime * 1000))

        -- Should complete in reasonable time (generous limits for CI)
        expect(addTime < 0.1).to.be.truthy() -- 100ms for adding nodes
        expect(renderTime < 1.0).to.be.truthy() -- 1000ms for rendering
    end)
end)
