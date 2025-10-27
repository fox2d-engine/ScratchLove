-- Project Validator Tests
-- Tests for project format validation (SB2 vs SB3 detection)

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect
local ProjectValidator = require("loader.project_validator")

describe("ProjectValidator", function()
    describe("isSB3", function()
        it("should accept valid SB3 project", function()
            local projectData = {
                meta = { semver = "3.0.0" },
                targets = {
                    { name = "Stage", isStage = true }
                }
            }
            local isValid, error = ProjectValidator.isSB3(projectData)
            expect(isValid).to.be.truthy()
            expect(error).to.equal(nil)
        end)

        it("should accept SB3 with version 3.x.x", function()
            local projectData = {
                meta = { semver = "3.1.0" },
                targets = { { name = "Stage" } }
            }
            local isValid, error = ProjectValidator.isSB3(projectData)
            expect(isValid).to.be.truthy()
            expect(error).to.equal(nil)
        end)

        it("should reject project without meta field", function()
            local projectData = {
                targets = { { name = "Stage" } }
            }
            local isValid, error = ProjectValidator.isSB3(projectData)
            expect(isValid).to.equal(false)
            expect(error).to.match("meta")
        end)

        it("should reject project without meta.semver field", function()
            local projectData = {
                meta = {},
                targets = { { name = "Stage" } }
            }
            local isValid, error = ProjectValidator.isSB3(projectData)
            expect(isValid).to.equal(false)
            expect(error).to.match("semver")
        end)

        it("should reject project with semver not starting with 3", function()
            local projectData = {
                meta = { semver = "2.0.0" },
                targets = { { name = "Stage" } }
            }
            local isValid, error = ProjectValidator.isSB3(projectData)
            expect(isValid).to.equal(false)
            expect(error).to.match("semver")
        end)

        it("should reject project without targets field", function()
            local projectData = {
                meta = { semver = "3.0.0" }
            }
            local isValid, error = ProjectValidator.isSB3(projectData)
            expect(isValid).to.equal(false)
            expect(error).to.match("targets")
        end)

        it("should reject project with non-table targets field", function()
            local projectData = {
                meta = { semver = "3.0.0" },
                targets = "not a table"
            }
            local isValid, error = ProjectValidator.isSB3(projectData)
            expect(isValid).to.equal(false)
            expect(error).to.match("array")
        end)

        it("should reject project with empty targets array", function()
            local projectData = {
                meta = { semver = "3.0.0" },
                targets = {}
            }
            local isValid, error = ProjectValidator.isSB3(projectData)
            expect(isValid).to.equal(false)
            expect(error).to.match("empty")
        end)

        it("should accept SB3 with multiple targets", function()
            local projectData = {
                meta = { semver = "3.0.0" },
                targets = {
                    { name = "Stage", isStage = true },
                    { name = "Sprite1", isStage = false },
                    { name = "Sprite2", isStage = false }
                }
            }
            local isValid, error = ProjectValidator.isSB3(projectData)
            expect(isValid).to.be.truthy()
            expect(error).to.equal(nil)
        end)
    end)

    describe("isSB2", function()
        it("should accept valid SB2 project", function()
            local projectData = {
                objName = "Stage",
                children = {}
            }
            local isValid, error = ProjectValidator.isSB2(projectData)
            expect(isValid).to.be.truthy()
            expect(error).to.equal(nil)
        end)

        it("should accept SB2 with sprites in children", function()
            local projectData = {
                objName = "Stage",
                children = {
                    { objName = "Sprite1" },
                    { objName = "Sprite2" }
                }
            }
            local isValid, error = ProjectValidator.isSB2(projectData)
            expect(isValid).to.be.truthy()
            expect(error).to.equal(nil)
        end)

        it("should reject project with meta field (SB3)", function()
            local projectData = {
                meta = { semver = "3.0.0" },
                objName = "Stage",
                children = {}
            }
            local isValid, error = ProjectValidator.isSB2(projectData)
            expect(isValid).to.equal(false)
            expect(error).to.match("meta")
        end)

        it("should reject project with targets field (SB3)", function()
            local projectData = {
                targets = {},
                objName = "Stage",
                children = {}
            }
            local isValid, error = ProjectValidator.isSB2(projectData)
            expect(isValid).to.equal(false)
            expect(error).to.match("targets")
        end)

        it("should reject project without children field", function()
            local projectData = {
                objName = "Stage"
            }
            local isValid, error = ProjectValidator.isSB2(projectData)
            expect(isValid).to.equal(false)
            expect(error).to.match("children")
        end)

        it("should reject project with non-table children field", function()
            local projectData = {
                objName = "Stage",
                children = "not a table"
            }
            local isValid, error = ProjectValidator.isSB2(projectData)
            expect(isValid).to.equal(false)
            expect(error).to.match("array")
        end)

        it("should reject project without objName field", function()
            local projectData = {
                children = {}
            }
            local isValid, error = ProjectValidator.isSB2(projectData)
            expect(isValid).to.equal(false)
            expect(error).to.match("objName")
        end)
    end)

    describe("validate", function()
        it("should detect valid SB3 project and return version 3", function()
            local projectData = {
                meta = { semver = "3.0.0" },
                targets = { { name = "Stage" } }
            }
            local version, error = ProjectValidator.validate(projectData)
            expect(version).to.equal(3)
            expect(error).to.equal(nil)
        end)

        it("should detect valid SB2 project and return version 2", function()
            local projectData = {
                objName = "Stage",
                children = {}
            }
            local version, error = ProjectValidator.validate(projectData)
            expect(version).to.equal(2)
            expect(error).to.equal(nil)
        end)

        it("should reject nil project data", function()
            local version, error = ProjectValidator.validate(nil)
            expect(version).to.equal(nil)
            expect(error).to.match("nil value")
        end)

        it("should reject non-table project data", function()
            local version, error = ProjectValidator.validate("not a table")
            expect(version).to.equal(nil)
            expect(error).to.match("expected table")
        end)

        it("should reject empty table", function()
            local version, error = ProjectValidator.validate({})
            expect(version).to.equal(nil)
            expect(error).to.match("empty table")
        end)

        it("should reject invalid project format with user-friendly message", function()
            local projectData = {
                invalidField = "invalid data"
            }
            local version, error = ProjectValidator.validate(projectData)
            expect(version).to.equal(nil)
            expect(error).to.match("Invalid project format")
            expect(error).to.match("Scratch 3.0")
        end)

        it("should prefer SB3 detection over SB2 when both could match", function()
            -- Edge case: project has SB3 fields
            local projectData = {
                meta = { semver = "3.0.0" },
                targets = { { name = "Stage" } }
            }
            local version, error = ProjectValidator.validate(projectData)
            expect(version).to.equal(3)
            expect(error).to.equal(nil)
        end)

        it("should handle SB3 with additional fields", function()
            local projectData = {
                meta = {
                    semver = "3.0.0",
                    vm = "0.2.0",
                    agent = "Mozilla/5.0"
                },
                targets = {
                    { name = "Stage", isStage = true }
                },
                monitors = {},
                extensions = {}
            }
            local version, error = ProjectValidator.validate(projectData)
            expect(version).to.equal(3)
            expect(error).to.equal(nil)
        end)

        it("should handle SB2 with additional fields", function()
            local projectData = {
                objName = "Stage",
                children = {},
                scripts = {},
                costumes = {},
                sounds = {},
                currentCostumeIndex = 0
            }
            local version, error = ProjectValidator.validate(projectData)
            expect(version).to.equal(2)
            expect(error).to.equal(nil)
        end)
    end)

    describe("edge cases", function()
        it("should handle project with numeric fields", function()
            local projectData = {
                [1] = "array element",
                meta = { semver = "3.0.0" },
                targets = { { name = "Stage" } }
            }
            local version, error = ProjectValidator.validate(projectData)
            expect(version).to.equal(3)
            expect(error).to.equal(nil)
        end)

        it("should handle project with nested data structures", function()
            local projectData = {
                meta = { semver = "3.0.0" },
                targets = {
                    {
                        name = "Stage",
                        blocks = {
                            block1 = { opcode = "event_whenflagclicked" }
                        },
                        variables = {
                            var1 = { "my variable", 0 }
                        }
                    }
                }
            }
            local version, error = ProjectValidator.validate(projectData)
            expect(version).to.equal(3)
            expect(error).to.equal(nil)
        end)

        it("should handle semver with pre-release tags", function()
            local projectData = {
                meta = { semver = "3.0.0-beta.1" },
                targets = { { name = "Stage" } }
            }
            local version, error = ProjectValidator.validate(projectData)
            expect(version).to.equal(3)
            expect(error).to.equal(nil)
        end)

        it("should reject semver that starts with 3 but is not dot-separated", function()
            local projectData = {
                meta = { semver = "300" },
                targets = { { name = "Stage" } }
            }
            local version, error = ProjectValidator.isSB3(projectData)
            expect(version).to.equal(false)
            expect(error).to.match("semver")
        end)
    end)
end)
