-- Unit Test: Monitor Real-time Updates
-- Tests that monitors evaluate and return real-time values, matching native Scratch behavior

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")

describe("Monitor Real-time Updates", function()

    describe("Motion monitors", function()
        it("should return real-time x position when sprite moves", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Create script: when flag clicked -> move 50 steps
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local moveId, moveBlock = SB3Builder.Motion.moveSteps(50)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, moveId, moveBlock)
            SB3Builder.linkBlocks(sprite, {hatId, moveId})

            -- Create project with x position monitor
            local projectJson = SB3Builder.createProject({stage, sprite})

            -- Add monitor for x position
            projectJson.monitors = {
                {
                    id = "monitor_x",
                    mode = "default",
                    opcode = "motion_xposition",
                    params = {},
                    spriteName = "TestSprite",
                    value = 0,
                    width = 0,
                    height = 0,
                    x = 5,
                    y = 5,
                    visible = true
                }
            }

            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Get sprite and monitor
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget).to.exist()
            expect(runtime.monitorManager).to.exist()

            local monitor = runtime.monitorManager.monitors["monitor_x"]
            expect(monitor).to.exist()
            expect(monitor.opcode).to.equal("motion_xposition")
            expect(monitor.targetRef).to.exist()

            -- Verify initial value
            local initialValue = monitor:getCurrentValue(runtime)
            expect(initialValue).to.equal(0)

            -- Run green flag
            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Sprite should have moved
            expect(spriteTarget).to.exist()
            expect(spriteTarget.x).to.equal(50)

            -- Monitor should return real-time value (matches native behavior)
            local updatedValue = monitor:getCurrentValue(runtime)
            expect(updatedValue).to.equal(50)
        end)

        it("should return real-time y position when sprite position changes", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Create script: when flag clicked -> set y to 100
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local setYId, setYBlock = SB3Builder.Motion.setY(100)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, setYId, setYBlock)
            SB3Builder.linkBlocks(sprite, {hatId, setYId})

            -- Create project with y position monitor
            local projectJson = SB3Builder.createProject({stage, sprite})
            projectJson.monitors = {
                {
                    id = "monitor_y",
                    mode = "default",
                    opcode = "motion_yposition",
                    params = {},
                    spriteName = "TestSprite",
                    value = 0,
                    width = 0,
                    height = 0,
                    x = 5,
                    y = 30,
                    visible = true
                }
            }

            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            local monitor = runtime.monitorManager.monitors["monitor_y"]

            expect(monitor).to.exist()
            expect(monitor:getCurrentValue(runtime)).to.equal(0)

            -- Execute script
            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Verify real-time value
            expect(spriteTarget).to.exist()
            expect(spriteTarget.y).to.equal(100)
            expect(monitor:getCurrentValue(runtime)).to.equal(100)
        end)

        it("should return real-time direction when sprite turns", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Create script: when flag clicked -> point in direction 180
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local pointId, pointBlock = SB3Builder.Motion.pointInDirection(180)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, pointId, pointBlock)
            SB3Builder.linkBlocks(sprite, {hatId, pointId})

            -- Create project with direction monitor
            local projectJson = SB3Builder.createProject({stage, sprite})
            projectJson.monitors = {
                {
                    id = "monitor_dir",
                    mode = "default",
                    opcode = "motion_direction",
                    params = {},
                    spriteName = "TestSprite",
                    value = 90,
                    width = 0,
                    height = 0,
                    x = 5,
                    y = 55,
                    visible = true
                }
            }

            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            local monitor = runtime.monitorManager.monitors["monitor_dir"]

            expect(monitor).to.exist()
            expect(monitor:getCurrentValue(runtime)).to.equal(90) -- Default direction

            -- Execute script
            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Verify real-time value
            expect(spriteTarget).to.exist()
            expect(spriteTarget.direction).to.equal(180)
            expect(monitor:getCurrentValue(runtime)).to.equal(180)
        end)
    end)

    describe("Variable monitors", function()
        it("should return real-time variable value through reference", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Add variable
            local varId = SB3Builder.addVariable(sprite, "testVar", 0)

            -- Create script: when flag clicked -> set testVar to 42
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local setId, setBlock = SB3Builder.Data.setVariable("testVar", 42, varId)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, setId, setBlock)
            SB3Builder.linkBlocks(sprite, {hatId, setId})

            -- Create project with variable monitor
            local projectJson = SB3Builder.createProject({stage, sprite})
            projectJson.monitors = {
                {
                    id = varId,
                    mode = "default",
                    opcode = "data_variable",
                    params = {
                        VARIABLE = "testVar"
                    },
                    spriteName = "TestSprite",
                    value = 0,
                    width = 0,
                    height = 0,
                    x = 5,
                    y = 5,
                    visible = true
                }
            }

            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local monitor = runtime.monitorManager.monitors[varId]

            expect(monitor).to.exist()
            expect(monitor.variableRef).to.exist()

            -- Initial value check (through reference)
            local initialValue = monitor:getCurrentValue(runtime)
            expect(initialValue).to.equal(0) -- Raw value (not JSON encoded)

            -- Execute script
            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Verify real-time value through variable reference
            local updatedValue = monitor:getCurrentValue(runtime)
            expect(updatedValue).to.equal(42) -- Raw value (not JSON encoded)
        end)
    end)

end)
