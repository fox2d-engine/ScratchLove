-- Operators Module
-- Implements all operator blocks (math, logic, text operations)

local Core = require("tests.sb3_builder.core")

local Operators = {}

-- ===== ARITHMETIC OPERATORS =====

---Create "+" (add) block
---@param num1 any First number
---@param num2 any Second number
---@return string id, SB3Builder.Block block
function Operators.add(num1, num2)
    return Core.createBlock("operator_add", {
        NUM1 = num1,
        NUM2 = num2
    })
end

---Create "-" (subtract) block
---@param num1 any First number
---@param num2 any Second number
---@return string id, SB3Builder.Block block
function Operators.subtract(num1, num2)
    return Core.createBlock("operator_subtract", {
        NUM1 = num1,
        NUM2 = num2
    })
end

---Create "*" (multiply) block
---@param num1 any First number
---@param num2 any Second number
---@return string id, SB3Builder.Block block
function Operators.multiply(num1, num2)
    return Core.createBlock("operator_multiply", {
        NUM1 = num1,
        NUM2 = num2
    })
end

---Create "/" (divide) block
---@param num1 any First number (dividend)
---@param num2 any Second number (divisor)
---@return string id, SB3Builder.Block block
function Operators.divide(num1, num2)
    return Core.createBlock("operator_divide", {
        NUM1 = num1,
        NUM2 = num2
    })
end

---Create "pick random" block
---@param from any From value
---@param to any To value
---@return string id, SB3Builder.Block block
function Operators.random(from, to)
    return Core.createBlock("operator_random", {
        FROM = from,
        TO = to
    })
end

-- ===== COMPARISON OPERATORS =====

---Create "<" (less than) block
---@param operand1 any First operand
---@param operand2 any Second operand
---@return string id, SB3Builder.Block block
function Operators.lessThan(operand1, operand2)
    return Core.createBlock("operator_lt", {
        OPERAND1 = operand1,
        OPERAND2 = operand2
    })
end

---Create "=" (equals) block
---@param operand1 any First operand
---@param operand2 any Second operand
---@return string id, SB3Builder.Block block
function Operators.equals(operand1, operand2)
    return Core.createBlock("operator_equals", {
        OPERAND1 = operand1,
        OPERAND2 = operand2
    })
end

---Create ">" (greater than) block
---@param operand1 any First operand
---@param operand2 any Second operand
---@return string id, SB3Builder.Block block
function Operators.greaterThan(operand1, operand2)
    return Core.createBlock("operator_gt", {
        OPERAND1 = operand1,
        OPERAND2 = operand2
    })
end

-- ===== LOGICAL OPERATORS =====

---Create "and" block
---@param operand1 any First boolean operand
---@param operand2 any Second boolean operand
---@return string id, SB3Builder.Block block
function Operators.and_(operand1, operand2)
    return Core.createBlock("operator_and", {
        OPERAND1 = operand1,
        OPERAND2 = operand2
    })
end

---Create "or" block
---@param operand1 any First boolean operand
---@param operand2 any Second boolean operand
---@return string id, SB3Builder.Block block
function Operators.or_(operand1, operand2)
    return Core.createBlock("operator_or", {
        OPERAND1 = operand1,
        OPERAND2 = operand2
    })
end

---Create "not" block
---@param operand any Boolean operand
---@return string id, SB3Builder.Block block
function Operators.not_(operand)
    return Core.createBlock("operator_not", {
        OPERAND = operand
    })
end

-- ===== STRING OPERATORS =====

---Create "join" block
---@param string1 any First string
---@param string2 any Second string
---@return string id, SB3Builder.Block block
function Operators.join(string1, string2)
    return Core.createBlock("operator_join", {
        STRING1 = string1,
        STRING2 = string2
    })
end

---Create "letter of" block
---@param letter any Letter position (1-based index)
---@param string any String to get letter from
---@return string id, SB3Builder.Block block
function Operators.letterOf(letter, string)
    return Core.createBlock("operator_letter_of", {
        LETTER = letter,
        STRING = string
    })
end

---Create "length of" block
---@param string any String to get length of
---@return string id, SB3Builder.Block block
function Operators.lengthOf(string)
    return Core.createBlock("operator_length", {
        STRING = string
    })
end

---Create "contains" block
---@param string1 any String to search in
---@param string2 any String to search for
---@return string id, SB3Builder.Block block
function Operators.contains(string1, string2)
    return Core.createBlock("operator_contains", {
        STRING1 = string1,
        STRING2 = string2
    })
end

-- ===== MATHEMATICAL FUNCTIONS =====

---Create "mod" (modulo) block
---@param num1 any Dividend
---@param num2 any Divisor
---@return string id, SB3Builder.Block block
function Operators.mod(num1, num2)
    return Core.createBlock("operator_mod", {
        NUM1 = num1,
        NUM2 = num2
    })
end

---Create "round" block
---@param num any Number to round
---@return string id, SB3Builder.Block block
function Operators.round(num)
    return Core.createBlock("operator_round", {
        NUM = num
    })
end

---Create math operation block
---@param operation string Math operation ("abs", "floor", "ceiling", "sqrt", "sin", "cos", "tan", "asin", "acos", "atan", "ln", "log", "e ^", "10 ^")
---@param num any Number input
---@return string id, SB3Builder.Block block
function Operators.mathop(operation, num)
    return Core.createBlock("operator_mathop", {
        NUM = num
    }, {
        OPERATOR = Core.field(operation)
    })
end

-- ===== CONVENIENCE FUNCTIONS FOR COMMON MATH OPERATIONS =====

---Create "abs" (absolute value) block
---@param num any Number input
---@return string id, SB3Builder.Block block
function Operators.abs(num)
    return Operators.mathop("abs", num)
end

---Create "floor" block
---@param num any Number input
---@return string id, SB3Builder.Block block
function Operators.floor(num)
    return Operators.mathop("floor", num)
end

---Create "ceiling" block
---@param num any Number input
---@return string id, SB3Builder.Block block
function Operators.ceiling(num)
    return Operators.mathop("ceiling", num)
end

---Create "sqrt" (square root) block
---@param num any Number input
---@return string id, SB3Builder.Block block
function Operators.sqrt(num)
    return Operators.mathop("sqrt", num)
end

---Create "sin" block
---@param num any Number input (degrees)
---@return string id, SB3Builder.Block block
function Operators.sin(num)
    return Operators.mathop("sin", num)
end

---Create "cos" block
---@param num any Number input (degrees)
---@return string id, SB3Builder.Block block
function Operators.cos(num)
    return Operators.mathop("cos", num)
end

---Create "tan" block
---@param num any Number input (degrees)
---@return string id, SB3Builder.Block block
function Operators.tan(num)
    return Operators.mathop("tan", num)
end

---Create "ln" (natural logarithm) block
---@param num any Number input
---@return string id, SB3Builder.Block block
function Operators.ln(num)
    return Operators.mathop("ln", num)
end

---Create "log" (base 10 logarithm) block
---@param num any Number input
---@return string id, SB3Builder.Block block
function Operators.log(num)
    return Operators.mathop("log", num)
end

---Create "e^" (e to the power) block
---@param num any Exponent
---@return string id, SB3Builder.Block block
function Operators.ePower(num)
    return Operators.mathop("e ^", num)
end

---Create "10^" (10 to the power) block
---@param num any Exponent
---@return string id, SB3Builder.Block block
function Operators.tenPower(num)
    return Operators.mathop("10 ^", num)
end

return Operators