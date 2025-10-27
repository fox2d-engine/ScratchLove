-- SB3 Builder Main Module
-- Unified entry point for creating Scratch 3.0 projects with DSL-style syntax
-- 
-- This module provides a comprehensive, type-safe, and test-friendly API for
-- programmatically creating Scratch 3.0 projects. It supports all block types,
-- nested inputs, and follows the official SB3 format specification.
--
-- Key Features:
-- ✅ Complete opcode coverage organized by category
-- ✅ DSL-style fluent syntax for better readability
-- ✅ Full LuaLS type annotations for safety
-- ✅ Support for nested inputs and complex block structures
-- ✅ Automatic ID management with reset capability
-- ✅ 1:1 compatibility with official SB3 format
--
-- Usage Examples:
--   local SB3 = require("tests.sb3_builder")
--   
--   -- Reset counter for clean tests
--   SB3.resetCounter()
--   
--   -- Create project structure
--   local stage = SB3.createStage()
--   local sprite = SB3.createSprite("Cat")
--   
--   -- Add variables and lists
--   local counterId = SB3.addVariable(stage, "counter", 0)
--   local listId = SB3.addList(sprite, "myList", {1, 2, 3})
--   
--   -- Create blocks using category modules
--   local hatId, hatBlock = SB3.Events.whenFlagClicked(100, 100)
--   local moveId, moveBlock = SB3.Motion.moveSteps(10)
--   local varId, varBlock, _ = SB3.Data.setVariable("counter", 1, counterId)
--   
--   -- Add blocks to targets
--   SB3.addBlock(sprite, hatId, hatBlock)
--   SB3.addBlock(sprite, moveId, moveBlock)
--   SB3.addBlock(sprite, varId, varBlock)
--   
--   -- Link blocks in execution order
--   SB3.linkBlocks(sprite, {hatId, moveId, varId})
--   
--   -- Generate complete project
--   local project = SB3.createProject({stage, sprite})

local Core = require("tests.sb3_builder.core")

-- Import all category modules
local Motion = require("tests.sb3_builder.motion")
local Events = require("tests.sb3_builder.events")
local Control = require("tests.sb3_builder.control")
local Data = require("tests.sb3_builder.data")
local Operators = require("tests.sb3_builder.operators")
local Looks = require("tests.sb3_builder.looks")
local Sensing = require("tests.sb3_builder.sensing")
local Procedures = require("tests.sb3_builder.procedures")

-- Main SB3Builder module
local SB3Builder = {}

-- ===== EXPOSE CORE FUNCTIONALITY =====

-- ID Management
SB3Builder.resetCounter = Core.resetCounter
SB3Builder.peekNextId = Core.peekNextId

-- Constants
SB3Builder.INPUT_SAME_BLOCK_SHADOW = Core.INPUT_SAME_BLOCK_SHADOW
SB3Builder.INPUT_BLOCK_NO_SHADOW = Core.INPUT_BLOCK_NO_SHADOW
SB3Builder.INPUT_DIFF_BLOCK_SHADOW = Core.INPUT_DIFF_BLOCK_SHADOW
SB3Builder.MATH_NUM_PRIMITIVE = Core.MATH_NUM_PRIMITIVE
SB3Builder.POSITIVE_NUM_PRIMITIVE = Core.POSITIVE_NUM_PRIMITIVE
SB3Builder.WHOLE_NUM_PRIMITIVE = Core.WHOLE_NUM_PRIMITIVE
SB3Builder.INTEGER_NUM_PRIMITIVE = Core.INTEGER_NUM_PRIMITIVE
SB3Builder.ANGLE_NUM_PRIMITIVE = Core.ANGLE_NUM_PRIMITIVE
SB3Builder.COLOR_PICKER_PRIMITIVE = Core.COLOR_PICKER_PRIMITIVE
SB3Builder.TEXT_PRIMITIVE = Core.TEXT_PRIMITIVE
SB3Builder.BROADCAST_PRIMITIVE = Core.BROADCAST_PRIMITIVE
SB3Builder.VAR_PRIMITIVE = Core.VAR_PRIMITIVE
SB3Builder.LIST_PRIMITIVE = Core.LIST_PRIMITIVE

-- Core Functions
SB3Builder.primitiveInput = Core.primitiveInput
SB3Builder.blockInput = Core.blockInput
SB3Builder.substackInput = Core.substackInput
SB3Builder.normalizeInput = Core.normalizeInput
SB3Builder.field = Core.field
SB3Builder.createBlock = Core.createBlock

-- Target Management
SB3Builder.createStage = Core.createStage
SB3Builder.createSprite = Core.createSprite
SB3Builder.addVariable = Core.addVariable
SB3Builder.addList = Core.addList
SB3Builder.addBroadcast = Core.addBroadcast
SB3Builder.addBlock = Core.addBlock
SB3Builder.linkBlocks = Core.linkBlocks

-- Asset Creation
SB3Builder.createCostume = Core.createCostume
SB3Builder.createSound = Core.createSound

-- Project Creation
SB3Builder.createProject = Core.createProject

-- ===== EXPOSE CATEGORY MODULES =====

-- Organize blocks by category for better discoverability
SB3Builder.Motion = Motion
SB3Builder.Events = Events  
SB3Builder.Control = Control
SB3Builder.Data = Data
SB3Builder.Operators = Operators
SB3Builder.Looks = Looks
SB3Builder.Sensing = Sensing
SB3Builder.Procedures = Procedures

-- ===== MODULE METADATA =====

SB3Builder._VERSION = "2.0.0"
SB3Builder._DESCRIPTION = "Modular SB3 Builder for Scratch 3.0 project creation"
SB3Builder._CATEGORIES = {"Motion", "Events", "Control", "Data", "Operators", "Looks", "Sensing", "Procedures"}

return SB3Builder