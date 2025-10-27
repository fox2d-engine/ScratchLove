-- SB3 Builder Type Definitions
-- Provides comprehensive LuaLS type annotations for Scratch 3.0 format

---@meta

-- SB3 Input Status Constants
---@alias SB3Builder.InputStatus
---| 1  # INPUT_SAME_BLOCK_SHADOW - unobscured shadow
---| 2  # INPUT_BLOCK_NO_SHADOW - no shadow  
---| 3  # INPUT_DIFF_BLOCK_SHADOW - obscured shadow

-- SB3 Primitive Type Constants
---@alias SB3Builder.PrimitiveType
---| 4  # MATH_NUM_PRIMITIVE - math_number
---| 5  # POSITIVE_NUM_PRIMITIVE - math_positive_number
---| 6  # WHOLE_NUM_PRIMITIVE - math_whole_number
---| 7  # INTEGER_NUM_PRIMITIVE - math_integer
---| 8  # ANGLE_NUM_PRIMITIVE - math_angle
---| 9  # COLOR_PICKER_PRIMITIVE - colour_picker
---| 10 # TEXT_PRIMITIVE - text
---| 11 # BROADCAST_PRIMITIVE - event_broadcast_menu
---| 12 # VAR_PRIMITIVE - data_variable
---| 13 # LIST_PRIMITIVE - data_listcontents

-- SB3 Value Types
---@alias SB3Builder.ScalarValue string|number|boolean

-- SB3 Input Value Types
---@alias SB3Builder.PrimitiveValue
---| [SB3Builder.PrimitiveType, SB3Builder.ScalarValue]             # Primitive value
---| [11, string, string]                                           # Broadcast primitive [type, name, id]
---| [12, string, string]                                           # Variable primitive [type, name, id] 
---| [13, string, string]                                           # List primitive [type, name, id]

---@alias SB3Builder.InputValue string|SB3Builder.PrimitiveValue

-- SB3 Input Structure
---@class SB3Builder.Input
---@field [1] SB3Builder.InputStatus Input status
---@field [2] SB3Builder.InputValue|nil Block ID or primitive value
---@field [3] SB3Builder.InputValue|nil Shadow block (for INPUT_DIFF_BLOCK_SHADOW)

-- SB3 Field Structure  
---@class SB3Builder.Field
---@field [1] string Field value
---@field [2] string|nil Field ID (for variables/lists/broadcasts)

-- SB3 Block Mutation
---@class SB3Builder.Mutation
---@field tagName string Always "mutation"
---@field children table[] Child mutations (usually empty)
---@field proccode string|nil Procedure code (for procedures)
---@field argumentnames string|nil JSON encoded argument names
---@field argumentids string|nil JSON encoded argument IDs
---@field argumentdefaults string|nil JSON encoded argument defaults
---@field warp string|nil "true" or "false" for warp mode

-- SB3 Block Structure
---@class SB3Builder.Block
---@field opcode string Block opcode
---@field inputs table<string, SB3Builder.Input> Block inputs
---@field fields table<string, SB3Builder.Field> Block fields
---@field next string|nil Next block ID
---@field parent string|nil Parent block ID
---@field shadow boolean Whether this is a shadow block
---@field topLevel boolean Whether this is a top-level block
---@field x number|nil X position (for top-level blocks)
---@field y number|nil Y position (for top-level blocks)
---@field mutation SB3Builder.Mutation|nil Block mutation data

-- SB3 Costume Structure
---@class SB3Builder.Costume
---@field assetId string 32-character asset ID
---@field dataFormat string Image format (png, svg, jpeg, etc.)
---@field name string Costume name
---@field md5ext string|nil MD5 hash with extension
---@field bitmapResolution number|nil Bitmap resolution (for non-SVG)
---@field rotationCenterX number|nil Rotation center X
---@field rotationCenterY number|nil Rotation center Y

-- SB3 Sound Structure
---@class SB3Builder.Sound
---@field assetId string 32-character asset ID
---@field dataFormat string Sound format (wav, mp3, etc.)
---@field name string Sound name
---@field md5ext string|nil MD5 hash with extension
---@field rate number|nil Sample rate
---@field sampleCount number|nil Sample count

-- SB3 Variable Structure  
---@alias SB3Builder.Variable [string, SB3Builder.ScalarValue, boolean?] # [name, value, isCloud?]

-- SB3 List Structure
---@alias SB3Builder.List [string, SB3Builder.ScalarValue[]] # [name, contents]

-- SB3 Target Structure
---@class SB3Builder.Target
---@field isStage boolean Whether this is the stage target
---@field name string Target name
---@field variables table<string, SB3Builder.Variable> Variables map (id -> variable)
---@field lists table<string, SB3Builder.List> Lists map (id -> list)
---@field broadcasts table<string, string> Broadcasts map (id -> name)
---@field blocks table<string, SB3Builder.Block> Blocks map (id -> block)
---@field comments table<string, table> Comments map
---@field currentCostume integer Current costume index
---@field costumes SB3Builder.Costume[] Costumes array
---@field sounds SB3Builder.Sound[] Sounds array
---@field volume number Volume level (0-100)
---@field layerOrder integer Layer order

-- SB3 Stage-specific Properties
---@class SB3Builder.Stage : SB3Builder.Target
---@field isStage true
---@field name "Stage"
---@field layerOrder 0
---@field tempo number Tempo (default 60)
---@field videoTransparency number Video transparency (0-100)
---@field videoState "on"|"off"|"on-flipped" Video state
---@field textToSpeechLanguage string|nil TTS language

-- SB3 Sprite-specific Properties
---@class SB3Builder.Sprite : SB3Builder.Target
---@field isStage false
---@field visible boolean Visibility
---@field x number X position
---@field y number Y position
---@field size number Size percentage
---@field direction number Direction in degrees
---@field draggable boolean Whether sprite is draggable
---@field rotationStyle "all around"|"left-right"|"don't rotate" Rotation style
---@field layerOrder integer Layer order (positive)

-- SB3 Project Structure
---@class SB3Builder.Project
---@field targets (SB3Builder.Stage|SB3Builder.Sprite)[] Array of targets
---@field monitors table[] Monitor objects
---@field extensions table[] Extension objects
---@field meta table Project metadata

-- Block Building Options
---@class SB3Builder.BlockOptions
---@field next string|nil Next block ID
---@field parent string|nil Parent block ID
---@field topLevel boolean|nil Whether block is top-level
---@field x number|nil X position (for top-level blocks)
---@field y number|nil Y position (for top-level blocks)
---@field shadow boolean|nil Whether this is a shadow block

-- Target Creation Options
---@class SB3Builder.TargetOptions
---@field currentCostume integer|nil Current costume index
---@field costumes SB3Builder.Costume[]|nil Costumes array
---@field sounds SB3Builder.Sound[]|nil Sounds array
---@field volume number|nil Volume level
---@field visible boolean|nil Visibility (sprites only)
---@field x number|nil X position (sprites only)
---@field y number|nil Y position (sprites only)
---@field size number|nil Size (sprites only)
---@field direction number|nil Direction (sprites only)
---@field draggable boolean|nil Draggable state (sprites only)
---@field rotationStyle string|nil Rotation style (sprites only)
---@field layerOrder integer|nil Layer order
---@field tempo number|nil Tempo (stage only)
---@field videoTransparency number|nil Video transparency (stage only)
---@field videoState string|nil Video state (stage only)

-- Fluent Builder Interface Types
---@class SB3Builder.BlockBuilder
---@field withInput fun(self: SB3Builder.BlockBuilder, name: string, value: any): SB3Builder.BlockBuilder
---@field withField fun(self: SB3Builder.BlockBuilder, name: string, value: string, id: string?): SB3Builder.BlockBuilder
---@field withNext fun(self: SB3Builder.BlockBuilder, nextId: string): SB3Builder.BlockBuilder
---@field withParent fun(self: SB3Builder.BlockBuilder, parentId: string): SB3Builder.BlockBuilder
---@field asTopLevel fun(self: SB3Builder.BlockBuilder, x: number?, y: number?): SB3Builder.BlockBuilder
---@field asShadow fun(self: SB3Builder.BlockBuilder): SB3Builder.BlockBuilder
---@field build fun(self: SB3Builder.BlockBuilder): string, SB3Builder.Block

---@class SB3Builder.ProjectBuilder
---@field addTarget fun(self: SB3Builder.ProjectBuilder, target: SB3Builder.Target): SB3Builder.ProjectBuilder
---@field addMonitor fun(self: SB3Builder.ProjectBuilder, monitor: table): SB3Builder.ProjectBuilder
---@field build fun(self: SB3Builder.ProjectBuilder): SB3Builder.Project

-- DSL Chain Builder Types for fluent syntax
---@class SB3Builder.ChainBuilder
---@field then_ fun(self: SB3Builder.ChainBuilder, blockId: string): SB3Builder.ChainBuilder
---@field build fun(self: SB3Builder.ChainBuilder): string[] Array of linked block IDs

return {}