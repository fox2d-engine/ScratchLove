---HC class system for object-oriented programming in Lua
---Provides class inheritance and object instantiation capabilities
---Part of the HardonCollider (HC) physics library

--[[
Copyright (c) 2010-2011 Matthias Richter

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

Except as contained in this notice, the name(s) of the above copyright holders
shall not be used in advertising or otherwise to promote the sale, use or
other dealings in this Software without prior written authorization.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
]]--

---@class HC_Class
---@field __index HC_Class
---@field __tostring function
---@field construct function
---@field inherit function
---@field __is_a table<HC_Class, boolean>
---@field is_a function

---@class HC_ClassArgs
---@field [1]? function Constructor function
---@field name? string Class name
---@field inherits? HC_Class|HC_Class[] Parent class(es) to inherit from

---Empty function placeholder
---@return nil
local function __NULL__() end

---Inherit functions and class hierarchy from parent classes
---@param class HC_Class Target class to add inheritance to
---@param interface? HC_Class Parent class to inherit from
---@param ... HC_Class Additional parent classes
---@return nil
local function inherit(class, interface, ...)
	if not interface then return end
	assert(type(interface) == "table", "Can only inherit from other classes.")

	-- __index and construct are not overwritten as for them class[name] is defined
	for name, func in pairs(interface) do
		if not class[name] then
			class[name] = func
		end
	end
	for super in pairs(interface.__is_a or {}) do
		class.__is_a[super] = true
	end

	return inherit(class, ...)
end

---Create a new class with optional inheritance
---@param args? function|HC_ClassArgs Constructor function or class configuration
---@return HC_Class class New class object
local function new(args)
	---@type HC_Class[]
	local super = {}
	local name = '<unnamed class>'
	---@type function
	local constructor = args or __NULL__
	if type(args) == "table" then
		-- nasty hack to check if args.inherits is a table of classes or a class or nil
		super = (args.inherits or {}).__is_a and {args.inherits} or args.inherits or {}
		name = args.name or name
		constructor = args[1] or __NULL__
	end
	assert(type(constructor) == "function", 'constructor has to be nil or a function')

	-- build class
	---@type HC_Class
	local class = {}
	class.__index = class
	class.__tostring = function() return ("<instance of %s>"):format(tostring(class)) end
	class.construct = constructor or __NULL__
	class.inherit = inherit
	class.__is_a = {[class] = true}
	class.is_a = function(self, other) return not not self.__is_a[other] end

	-- inherit superclasses (see above)
	inherit(class, unpack(super))

	-- syntactic sugar
	local meta = {
		__call = function(self, ...)
			local obj = {}
			setmetatable(obj, self)
			self.construct(obj, ...)
			return obj
		end,
		__tostring = function() return name end
	}
	return setmetatable(class, meta)
end

---Interface for cross class-system compatibility (see https://github.com/bartbes/Class-Commons)
---@type table<string, function>
if common_class ~= false and not common then
	common = {}
	---Create class using Class-Commons interface
	---@param name string Class name
	---@param prototype table Class prototype with methods
	---@param parent? table Parent class prototype
	---@return HC_Class class New class
	function common.class(name, prototype, parent)
		local init = prototype.init or (parent or {}).init
		return new{name = name, inherits = {prototype, parent}, init}
	end
	---Create instance using Class-Commons interface
	---@param class HC_Class Class to instantiate
	---@param ... any Constructor arguments
	---@return table instance New instance
	function common.instance(class, ...)
		return class(...)
	end
end

---HC class module
---@class HC_ClassModule
---@field new function Create new class
---@field inherit function Add inheritance to class
---@overload fun(...): HC_Class
return setmetatable({new = new, inherit = inherit},
	{__call = function(_,...) return new(...) end})
