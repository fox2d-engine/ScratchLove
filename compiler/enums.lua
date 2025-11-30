
---Input type enum for type inference and optimization
---Uses bit flags to represent type possibilities
---@enum InputType
local InputType = {
    -- Number type breakdown
    NUMBER_POS_INF = 0x001,    -- +Infinity
    NUMBER_POS_INT = 0x002,    -- 1, 2, 3, ...
    NUMBER_POS_FRACT = 0x004,  -- 0.5, 1.5, ...
    NUMBER_ZERO = 0x008,       -- 0
    NUMBER_NEG_ZERO = 0x010,   -- -0
    NUMBER_NEG_INT = 0x020,    -- -1, -2, -3, ...
    NUMBER_NEG_FRACT = 0x040,  -- -0.5, -1.5, ...
    NUMBER_NEG_INF = 0x080,    -- -Infinity
    NUMBER_NAN = 0x100,        -- NaN

    -- String type breakdown
    STRING_NUM = 0x200,        -- "123", "3.14"
    STRING_NAN = 0x400,        -- "hello", ""
    STRING_BOOLEAN = 0x800,    -- "true", "false"

    -- Boolean type
    BOOLEAN = 0x1000,          -- true, false

    -- Composite types (computed via bit operations)
    NUMBER_POS_REAL = 0x006,   -- NUMBER_POS_INT | NUMBER_POS_FRACT (positive excluding 0 and Infinity)
    NUMBER_NEG_REAL = 0x060,   -- NUMBER_NEG_INT | NUMBER_NEG_FRACT (negative excluding -0 and -Infinity)
    NUMBER_ANY_ZERO = 0x018,   -- NUMBER_ZERO | NUMBER_NEG_ZERO (either 0 or -0)
    NUMBER_INF = 0x081,        -- NUMBER_POS_INF | NUMBER_NEG_INF (either Infinity or -Infinity)
    NUMBER_POS = 0x007,        -- NUMBER_POS_REAL | NUMBER_POS_INF (any positive number, excluding 0)
    NUMBER_NEG = 0x0E0,        -- NUMBER_NEG_REAL | NUMBER_NEG_INF (any negative number, excluding -0)
    NUMBER_WHOLE = 0x00A,      -- NUMBER_POS_INT | NUMBER_ZERO (any whole number >= 0)
    NUMBER_INT = 0x03A,        -- NUMBER_POS_INT | NUMBER_ANY_ZERO | NUMBER_NEG_INT (any integer)
    NUMBER_INDEX = 0x1BB,      -- NUMBER_INT | NUMBER_INF | NUMBER_NAN (any number that works as array index)
    NUMBER_FRACT = 0x044,      -- NUMBER_POS_FRACT | NUMBER_NEG_FRACT (any fractional non-integer)
    NUMBER_REAL = 0x07E,       -- NUMBER_POS_REAL | NUMBER_ANY_ZERO | NUMBER_NEG_REAL (any real number)

    NUMBER = 0x0FF,            -- NUMBER_REAL | NUMBER_INF (all numbers excluding NaN)
    NUMBER_OR_NAN = 0x1FF,     -- NUMBER | NUMBER_NAN (all numbers including NaN)
    NUMBER_INTERPRETABLE = 0x12FF, -- NUMBER | STRING_NUM | BOOLEAN (anything that can be interpreted as number)

    STRING = 0xE00,            -- STRING_NUM | STRING_NAN | STRING_BOOLEAN (all strings)

    BOOLEAN_INTERPRETABLE = 0x1800, -- BOOLEAN | STRING_BOOLEAN (any input that can be interpreted as boolean)

    ANY = 0x1FFF,              -- NUMBER_OR_NAN | STRING | BOOLEAN (any value type a Scratch variable can hold)

    -- Special types
    COLOR = 0x2000             -- [R, G, B] color array
}

---Stack operation codes for executable blocks
---@enum StackOpcode
local StackOpcode = {
    -- No operation
    NOP = "noop",

    -- Control flow
    CONTROL_IF_ELSE = "control.if",
    CONTROL_WHILE = "control.while",
    CONTROL_FOR = "control.for",
    CONTROL_REPEAT = "control.repeat",
    CONTROL_REPEAT_UNTIL = "control.repeatUntil",
    CONTROL_FOREVER = "control.forever",
    CONTROL_WAIT = "control.wait",
    CONTROL_WAIT_UNTIL = "control.waitUntil",
    CONTROL_STOP_ALL = "control.stopAll",
    CONTROL_STOP_OTHERS = "control.stopOthers",
    CONTROL_STOP_SCRIPT = "control.stopScript",
    CONTROL_CLONE_CREATE = "control.createClone",
    CONTROL_CLONE_DELETE = "control.deleteClone",
    CONTROL_WARP = "control.warp",
    CONTROL_INCR_COUNTER = "control.incrCounter",
    CONTROL_CLEAR_COUNTER = "control.clearCounter",

    -- Variables
    VAR_SET = "var.set",
    VAR_SHOW = "var.show",
    VAR_HIDE = "var.hide",

    -- Lists
    LIST_ADD = "list.add",
    LIST_INSERT = "list.insert",
    LIST_DELETE = "list.delete",
    LIST_DELETE_ALL = "list.deleteAll",
    LIST_REPLACE = "list.replace",
    LIST_SHOW = "list.show",
    LIST_HIDE = "list.hide",

    -- Motion
    MOTION_X_SET = "motion.setX",
    MOTION_Y_SET = "motion.setY",
    MOTION_XY_SET = "motion.setXY",
    MOTION_STEP = "motion.step",
    MOTION_TURN_RIGHT = "motion.turnRight",
    MOTION_TURN_LEFT = "motion.turnLeft",
    MOTION_DIRECTION_SET = "motion.setDirection",
    MOTION_GOTO = "motion.goto",
    MOTION_POINT_TOWARDS = "motion.pointTowards",
    MOTION_GLIDE_TO = "motion.glideTo",
    MOTION_GLIDE_TO_XY = "motion.glideXY",
    MOTION_X_CHANGE = "motion.changeX",
    MOTION_Y_CHANGE = "motion.changeY",
    MOTION_IF_ON_EDGE_BOUNCE = "motion.edgeBounce",
    MOTION_SET_ROTATION_STYLE = "motion.setRotationStyle",

    -- Stage-specific motion
    MOTION_ALIGN_SCENE = "motion.alignScene",
    MOTION_SCROLL_RIGHT = "motion.scrollRight",
    MOTION_SCROLL_UP = "motion.scrollUp",

    -- Looks
    LOOKS_SHOW = "looks.show",
    LOOKS_HIDE = "looks.hide",
    LOOKS_COSTUME_SET = "looks.setCostume",
    LOOKS_SIZE_SET = "looks.setSize",
    LOOKS_SIZE_CHANGE = "looks.changeSize",
    LOOKS_EFFECT_SET = "looks.setEffect",
    LOOKS_EFFECT_CHANGE = "looks.changeEffect",
    LOOKS_EFFECT_CLEAR = "looks.clearEffects",
    LOOKS_COSTUME_NEXT = "looks.nextCostume",
    LOOKS_BACKDROP_SET = "looks.setBackdrop",
    LOOKS_BACKDROP_NEXT = "looks.nextBackdrop",
    LOOKS_LAYER_FRONT = "looks.goToFront",
    LOOKS_LAYER_BACK = "looks.goToBack",
    LOOKS_LAYER_FORWARD = "looks.goForward",
    LOOKS_LAYER_BACKWARD = "looks.goBackward",
    LOOKS_SAY = "looks.say",
    LOOKS_SAY_FOR_SECS = "looks.sayForSecs",
    LOOKS_THINK = "looks.think",
    LOOKS_THINK_FOR_SECS = "looks.thinkForSecs",
    LOOKS_STRETCH_CHANGE = "looks.changeStretch",
    LOOKS_STRETCH_SET = "looks.setStretch",
    LOOKS_HIDE_ALL_SPRITES = "looks.hideAllSprites",
    LOOKS_SWITCH_BACKDROP_AND_WAIT = "looks.switchBackdropAndWait",

    -- Sound
    SOUND_PLAY = "sound.play",
    SOUND_PLAY_UNTIL_DONE = "sound.playUntilDone",
    SOUND_STOP_ALL = "sound.stopAll",
    SOUND_VOLUME_CHANGE = "sound.changeVolume",
    SOUND_VOLUME_SET = "sound.setVolume",
    SOUND_EFFECT_CHANGE = "sound.changeEffect",
    SOUND_EFFECT_SET = "sound.setEffect",
    SOUND_EFFECT_CLEAR = "sound.clearEffects",

    -- Events
    EVENT_BROADCAST = "event.broadcast",
    EVENT_BROADCAST_AND_WAIT = "event.broadcastAndWait",

    -- Procedures
    PROCEDURE_CALL = "procedures.call",
    PROCEDURE_RETURN = "procedures.return",

    -- Pen operations
    PEN_CLEAR = "pen.clear",
    PEN_DOWN = "pen.down",
    PEN_UP = "pen.up",
    PEN_COLOR_SET = "pen.setColor",
    PEN_COLOR_CHANGE_PARAM = "pen.changeColorParam",
    PEN_COLOR_SET_PARAM = "pen.setColorParam",
    PEN_SIZE_CHANGE = "pen.changeSize",
    PEN_SIZE_SET = "pen.setSize",
    PEN_STAMP = "pen.stamp",
    PEN_TRANSPARENCY_SET = "pen.setTransparency",
    PEN_TRANSPARENCY_CHANGE = "pen.changeTransparency",
    PEN_SHADE_SET = "pen.setShade",
    PEN_SHADE_CHANGE = "pen.changeShade",
    PEN_HUE_SET = "pen.setHue",
    PEN_HUE_CHANGE = "pen.changeHue",

    -- Sensing operations
    SENSING_TIMER_RESET = "sensing.resetTimer",
    SENSING_ASK_AND_WAIT = "sensing.askAndWait",
    SENSING_SET_DRAG_MODE = "sensing.setDragMode",

    -- Extensions (future expansion)
    ADDON_CALL = "addons.call"
}

---Input operation codes for expressions and values
---@enum InputOpcode
local InputOpcode = {
    -- Constants
    CONSTANT = "constant",

    -- Math operations
    OP_ADD = "op.add",
    OP_SUBTRACT = "op.subtract",
    OP_MULTIPLY = "op.multiply",
    OP_DIVIDE = "op.divide",
    OP_MOD = "op.mod",
    OP_ROUND = "op.round",
    OP_MATHOP = "op.mathop",
    OP_RANDOM = "op.random",

    -- Logic operations
    OP_AND = "op.and",
    OP_OR = "op.or",
    OP_NOT = "op.not",

    -- Comparison operations
    OP_EQUALS = "op.equals",
    OP_GREATER = "op.greater",
    OP_LESS = "op.less",

    -- String operations
    OP_JOIN = "op.join",
    OP_LETTER_OF = "op.letterOf",
    OP_LENGTH = "op.length",
    OP_CONTAINS = "op.contains",

    -- Variables and lists
    VAR_GET = "var.get",
    LIST_GET = "list.get",
    LIST_LENGTH = "list.length",
    LIST_CONTAINS = "list.contains",
    LIST_CONTENTS = "list.contents",
    LIST_INDEX_OF = "list.indexOf",

    -- Type casting
    CAST_NUMBER = "cast.number",
    CAST_NUMBER_OR_NAN = "cast.numberOrNaN",
    CAST_STRING = "cast.string",
    CAST_BOOLEAN = "cast.boolean",

    -- Sensing
    SENSING_MOUSE_X = "sensing.mouseX",
    SENSING_MOUSE_Y = "sensing.mouseY",
    SENSING_MOUSE_DOWN = "sensing.mouseDown",
    SENSING_KEY_DOWN = "sensing.keyDown",
    SENSING_TIMER_GET = "sensing.timer",
    SENSING_TOUCHING_OBJECT = "sensing.touchingObject",
    SENSING_TOUCHING_COLOR = "sensing.touchingColor",
    SENSING_COLOR_TOUCHING_COLOR = "sensing.colorTouchingColor",
    SENSING_DISTANCE_TO = "sensing.distanceTo",
    SENSING_ANSWER = "sensing.answer",
    SENSING_LOUDNESS = "sensing.loudness",
    SENSING_OF = "sensing.of",
    SENSING_CURRENT = "sensing.current",
    SENSING_DAYS_SINCE_2000 = "sensing.daysSince2000",
    SENSING_USERNAME = "sensing.username",
    SENSING_USER_ID = "sensing.userId",

    -- Control sensing
    CONTROL_COUNTER_GET = "control.getCounter",

    -- Motion sensing
    MOTION_X_GET = "motion.getX",
    MOTION_Y_GET = "motion.getY",
    MOTION_DIRECTION_GET = "motion.getDirection",
    MOTION_X_SCROLL = "motion.getXScroll",
    MOTION_Y_SCROLL = "motion.getYScroll",

    -- Looks sensing
    LOOKS_COSTUME_NUMBER = "looks.costumeNumber",
    LOOKS_COSTUME_NAME = "looks.costumeName",
    LOOKS_BACKDROP_NUMBER = "looks.backdropNumber",
    LOOKS_BACKDROP_NAME = "looks.backdropName",
    LOOKS_SIZE = "looks.size",

    -- Sound sensing
    SOUND_VOLUME = "sound.volume",

    -- Procedures
    ARG_REF = "arg.ref",
    PROCEDURE_CALL = "procedure.call"
}

return {
    InputType = InputType,
    StackOpcode = StackOpcode,
    InputOpcode = InputOpcode
}
