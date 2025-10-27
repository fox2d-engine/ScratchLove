local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local Cast = require("utils.cast")

describe("Cast utility functions", function()
    describe("toNumber", function()
        it("should convert numeric values correctly", function()
            expect(Cast.toNumber(0)).to.equal(0)
            expect(Cast.toNumber(1)).to.equal(1)
            expect(Cast.toNumber(3.14)).to.equal(3.14)
        end)

        it("should convert string values correctly", function()
            expect(Cast.toNumber("0")).to.equal(0)
            expect(Cast.toNumber("1")).to.equal(1)
            expect(Cast.toNumber("3.14")).to.equal(3.14)
            expect(Cast.toNumber("0.1e10")).to.equal(1000000000)
            expect(Cast.toNumber("foobar")).to.equal(0)
        end)

        it("should convert boolean values correctly", function()
            expect(Cast.toNumber(true)).to.equal(1)
            expect(Cast.toNumber(false)).to.equal(0)
            -- Boolean strings should be treated as strings and return 0
            expect(Cast.toNumber("true")).to.equal(0)
            expect(Cast.toNumber("false")).to.equal(0)
        end)

        it("should handle undefined and object values", function()
            expect(Cast.toNumber(nil)).to.equal(0)
            expect(Cast.toNumber({})).to.equal(0)
            expect(Cast.toNumber(0/0)).to.equal(0) -- NaN should convert to 0
        end)

        it("should handle infinity cases correctly", function()
            expect(Cast.toNumber("Infinity")).to.equal(math.huge)
            expect(Cast.toNumber("-Infinity")).to.equal(-math.huge)
            -- Other infinity variants should return 0 to match JavaScript behavior
            expect(Cast.toNumber("infinity")).to.equal(0)
            expect(Cast.toNumber("INFINITY")).to.equal(0)
        end)

        it("should handle whitespace", function()
            expect(Cast.toNumber("  42  ")).to.equal(42)
            expect(Cast.toNumber("   ")).to.equal(0)
            expect(Cast.toNumber("")).to.equal(0)
        end)
    end)

    describe("toBoolean", function()
        it("should convert numeric values correctly", function()
            expect(Cast.toBoolean(0)).to.equal(false)
            expect(Cast.toBoolean(1)).to.equal(true)
            expect(Cast.toBoolean(3.14)).to.equal(true)
            expect(Cast.toBoolean(-1)).to.equal(true)
        end)

        it("should convert string values correctly", function()
            expect(Cast.toBoolean("0")).to.equal(false) -- Original Scratch behavior
            expect(Cast.toBoolean("1")).to.equal(true)
            expect(Cast.toBoolean("3.14")).to.equal(true)
            expect(Cast.toBoolean("0.1e10")).to.equal(true)
            expect(Cast.toBoolean("foobar")).to.equal(true)
            expect(Cast.toBoolean("")).to.equal(false)
            expect(Cast.toBoolean("false")).to.equal(false)
            expect(Cast.toBoolean("FALSE")).to.equal(false)
            expect(Cast.toBoolean("  false  ")).to.equal(false)
        end)

        it("should convert boolean values correctly", function()
            expect(Cast.toBoolean(true)).to.equal(true)
            expect(Cast.toBoolean(false)).to.equal(false)
        end)

        it("should handle undefined and object values", function()
            expect(Cast.toBoolean(nil)).to.equal(false)
            expect(Cast.toBoolean({})).to.equal(true)
        end)

        it("should handle NaN correctly", function()
            expect(Cast.toBoolean(0/0)).to.equal(false) -- NaN should be falsy
        end)
    end)

    describe("toString", function()
        it("should convert numeric values correctly", function()
            expect(Cast.toString(0)).to.equal("0")
            expect(Cast.toString(1)).to.equal("1")
            expect(Cast.toString(3.14)).to.equal("3.14")
        end)

        it("should convert string values correctly", function()
            expect(Cast.toString("0")).to.equal("0")
            expect(Cast.toString("1")).to.equal("1")
            expect(Cast.toString("3.14")).to.equal("3.14")
            expect(Cast.toString("0.1e10")).to.equal("0.1e10")
            expect(Cast.toString("foobar")).to.equal("foobar")
        end)

        it("should convert boolean values correctly", function()
            expect(Cast.toString(true)).to.equal("true")
            expect(Cast.toString(false)).to.equal("false")
        end)

        it("should handle undefined and object values", function()
            expect(Cast.toString(nil)).to.equal("undefined") -- Original Scratch behavior
            expect(Cast.toString({})).to.equal("[object Object]") -- Original Scratch behavior
        end)

        it("should handle infinity and NaN", function()
            expect(Cast.toString(math.huge)).to.equal("Infinity")
            expect(Cast.toString(-math.huge)).to.equal("-Infinity")
            expect(Cast.toString(0/0)).to.equal("NaN")
        end)

        it("should format numbers correctly", function()
            expect(Cast.toString(1.0)).to.equal("1")
            expect(Cast.toString(1.5)).to.equal("1.5")
            expect(Cast.toString(1.50000)).to.equal("1.5")
        end)
    end)

    describe("compare", function()
        it("should compare numeric values correctly", function()
            expect(Cast.compare(0, 0)).to.equal(0)
            expect(Cast.compare(1, 0)).to.equal(1)
            expect(Cast.compare(0, 1)).to.equal(-1)
            expect(Cast.compare(1, 1)).to.equal(0)
        end)

        it("should compare string values correctly", function()
            expect(Cast.compare("0", "0")).to.equal(0)
            expect(Cast.compare("0.1e10", "1000000000")).to.equal(0)
            expect(Cast.compare("foobar", "FOOBAR")).to.equal(0) -- Case insensitive
            expect(Cast.compare("dog", "cat") > 0).to.equal(true)
        end)

        it("should compare boolean values correctly", function()
            expect(Cast.compare(true, true)).to.equal(0)
            expect(Cast.compare(true, false)).to.equal(1)
            expect(Cast.compare(false, true)).to.equal(-1)
        end)

        it("should handle undefined and object values", function()
            expect(Cast.compare(nil, nil)).to.equal(0)
            expect(Cast.compare(nil, "undefined")).to.equal(0) -- Original Scratch: undefined vs 'undefined'
            expect(Cast.compare({}, {})).to.equal(0) -- Original Scratch behavior
            expect(Cast.compare({}, "[object Object]")).to.equal(0) -- Original Scratch behavior
        end)

        it("should handle mixed numeric and string comparisons", function()
            expect(Cast.compare("5", 5)).to.equal(0) -- Both are numbers
            expect(Cast.compare("abc", 5)).to.equal(1) -- String vs number, compare as strings
        end)

        it("should handle infinity comparisons", function()
            expect(Cast.compare(math.huge, math.huge)).to.equal(0)
            expect(Cast.compare(-math.huge, -math.huge)).to.equal(0)
            expect(Cast.compare(math.huge, 100)).to.equal(1)
            expect(Cast.compare(-math.huge, 100)).to.equal(-1)
        end)
    end)

    describe("isNumber", function()
        it("should identify numeric values correctly", function()
            expect(Cast.isNumber(0)).to.equal(true)
            expect(Cast.isNumber(1)).to.equal(true)
            expect(Cast.isNumber(3.14)).to.equal(true)
            expect(Cast.isNumber(-1)).to.equal(true)
        end)

        it("should identify string numbers correctly", function()
            expect(Cast.isNumber("0")).to.equal(true)
            expect(Cast.isNumber("1")).to.equal(true)
            expect(Cast.isNumber("3.14")).to.equal(true)
            expect(Cast.isNumber("0.1e10")).to.equal(true)
            expect(Cast.isNumber("")).to.equal(true) -- Empty string converts to 0
            expect(Cast.isNumber("Infinity")).to.equal(true)
            expect(Cast.isNumber("-Infinity")).to.equal(true)
            expect(Cast.isNumber("foobar")).to.equal(false)
        end)

        it("should identify boolean values as numbers", function()
            expect(Cast.isNumber(true)).to.equal(true)
            expect(Cast.isNumber(false)).to.equal(true)
        end)

        it("should handle non-numeric values", function()
            expect(Cast.isNumber(nil)).to.equal(false)
            expect(Cast.isNumber({})).to.equal(false)
        end)

        it("should handle NaN correctly", function()
            expect(Cast.isNumber(0/0)).to.equal(false) -- NaN is not a valid number
        end)
    end)

    describe("toListIndex", function()
        local listLength = 6
        local emptyLength = 0

        it("should handle valid indices", function()
            expect(Cast.toListIndex(1, listLength, false)).to.equal(1)
            expect(Cast.toListIndex(6, listLength, false)).to.equal(6)
        end)

        it("should handle invalid indices", function()
            expect(Cast.toListIndex(-1, listLength, false)).to.equal(Cast.LIST_INVALID)
            expect(Cast.toListIndex(0.1, listLength, false)).to.equal(Cast.LIST_INVALID)
            expect(Cast.toListIndex(0, listLength, false)).to.equal(Cast.LIST_INVALID)
            expect(Cast.toListIndex(7, listLength, false)).to.equal(Cast.LIST_INVALID)
        end)

        it("should handle 'all' index", function()
            expect(Cast.toListIndex("all", listLength, true)).to.equal(Cast.LIST_ALL)
            expect(Cast.toListIndex("all", listLength, false)).to.equal(Cast.LIST_INVALID)
        end)

        it("should handle 'last' index", function()
            expect(Cast.toListIndex("last", listLength, false)).to.equal(listLength)
            expect(Cast.toListIndex("last", emptyLength, false)).to.equal(Cast.LIST_INVALID)
        end)

        it("should handle 'random' index", function()
            local randomIndex = Cast.toListIndex("random", listLength, false)
            expect(randomIndex <= listLength).to.equal(true)
            expect(randomIndex > 0).to.equal(true)
            expect(Cast.toListIndex("random", emptyLength, false)).to.equal(Cast.LIST_INVALID)
        end)

        it("should handle 'any' index (alias for random)", function()
            local anyIndex = Cast.toListIndex("any", listLength, false)
            expect(anyIndex <= listLength).to.equal(true)
            expect(anyIndex > 0).to.equal(true)
            expect(Cast.toListIndex("any", emptyLength, false)).to.equal(Cast.LIST_INVALID)
        end)

        it("should convert string numbers to indices", function()
            expect(Cast.toListIndex("3", listLength, false)).to.equal(3)
            expect(Cast.toListIndex("3.9", listLength, false)).to.equal(3) -- Should floor
        end)
    end)

    describe("hexToRGB", function()
        it("should convert hex colors to RGB (0-1 range)", function()
            local black = Cast.hexToRGB("#000000")
            expect(black.r).to.equal(0)
            expect(black.g).to.equal(0)
            expect(black.b).to.equal(0)

            local white = Cast.hexToRGB("#FFFFFF")
            expect(white.r).to.equal(1)
            expect(white.g).to.equal(1)
            expect(white.b).to.equal(1)

            local red = Cast.hexToRGB("#FF0000")
            expect(red.r).to.equal(1)
            expect(red.g).to.equal(0)
            expect(red.b).to.equal(0)
        end)

        it("should handle hex colors without # prefix", function()
            local blue = Cast.hexToRGB("0000FF")
            expect(blue.r).to.equal(0)
            expect(blue.g).to.equal(0)
            expect(blue.b).to.equal(1)
        end)

        it("should return nil for invalid hex colors", function()
            expect(Cast.hexToRGB("#fff")).to.equal(nil) -- Wrong length
            expect(Cast.hexToRGB("#GGGGGG")).to.equal(nil) -- Invalid hex
            expect(Cast.hexToRGB("invalid")).to.equal(nil)
            expect(Cast.hexToRGB(nil)).to.equal(nil)
        end)
    end)

    describe("rgbToHex", function()
        it("should convert RGB values to hex", function()
            expect(Cast.rgbToHex(0, 0, 0)).to.equal("#000000")
            expect(Cast.rgbToHex(1, 1, 1)).to.equal("#FFFFFF")
            expect(Cast.rgbToHex(1, 0, 0)).to.equal("#FF0000")
            expect(Cast.rgbToHex(0, 1, 0)).to.equal("#00FF00")
            expect(Cast.rgbToHex(0, 0, 1)).to.equal("#0000FF")
        end)

        it("should clamp values to 0-1 range", function()
            expect(Cast.rgbToHex(-0.5, 1.5, 0.5)).to.equal("#00FF80")
        end)

        it("should handle nil values", function()
            expect(Cast.rgbToHex(nil, nil, nil)).to.equal("#000000")
        end)
    end)

    describe("hexToRGB255", function()
        it("should convert hex colors to RGB (0-255 range)", function()
            local black = Cast.hexToRGB255("#000000")
            expect(black.r).to.equal(0)
            expect(black.g).to.equal(0)
            expect(black.b).to.equal(0)

            local white = Cast.hexToRGB255("#FFFFFF")
            expect(white.r).to.equal(255)
            expect(white.g).to.equal(255)
            expect(white.b).to.equal(255)

            local red = Cast.hexToRGB255("#FF0000")
            expect(red.r).to.equal(255)
            expect(red.g).to.equal(0)
            expect(red.b).to.equal(0)
        end)

        it("should return nil for invalid hex colors", function()
            expect(Cast.hexToRGB255("#fff")).to.equal(nil)
            expect(Cast.hexToRGB255("invalid")).to.equal(nil)
        end)
    end)

    describe("wrapClamp", function()
        it("should wrap values within range", function()
            expect(Cast.wrapClamp(5, 1, 10)).to.equal(5)
            expect(Cast.wrapClamp(0, 1, 10)).to.equal(10)
            expect(Cast.wrapClamp(11, 1, 10)).to.equal(1)
            expect(Cast.wrapClamp(12, 1, 10)).to.equal(2)
        end)

        it("should handle negative values", function()
            expect(Cast.wrapClamp(-1, 1, 10)).to.equal(9)
            expect(Cast.wrapClamp(-2, 1, 10)).to.equal(8)
        end)
    end)
end)