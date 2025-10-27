-- Test: Stable Compilation Order
-- Verifies that multiple compilations of the same project produce identical output

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local json = require("lib.json")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")
local ProjectCompiler = require("compiler.project_compiler")

describe("Stable Compilation Order", function()
    it("should produce identical compilation output on multiple runs", function()
        -- Create a simple project with multiple hat blocks
        local projectJson = [[{
            "targets": [{
                "isStage": true,
                "name": "Stage",
                "variables": {},
                "lists": {},
                "broadcasts": {},
                "blocks": {
                    "block1": {
                        "opcode": "event_whenflagclicked",
                        "next": null,
                        "parent": null,
                        "inputs": {},
                        "fields": {},
                        "shadow": false,
                        "topLevel": true,
                        "x": 0,
                        "y": 0
                    },
                    "block2": {
                        "opcode": "event_whenkeypressed",
                        "next": null,
                        "parent": null,
                        "inputs": {},
                        "fields": {
                            "KEY_OPTION": ["space", null]
                        },
                        "shadow": false,
                        "topLevel": true,
                        "x": 0,
                        "y": 100
                    },
                    "block3": {
                        "opcode": "event_whenbroadcastreceived",
                        "next": null,
                        "parent": null,
                        "inputs": {},
                        "fields": {
                            "BROADCAST_OPTION": ["message1", "msg1"]
                        },
                        "shadow": false,
                        "topLevel": true,
                        "x": 0,
                        "y": 200
                    }
                },
                "costumes": [],
                "sounds": [],
                "currentCostume": 0,
                "volume": 100,
                "tempo": 60
            }],
            "meta": {}
        }]]

        local compiledSources = {}

        -- Compile the same project 3 times
        for i = 1, 3 do
            local projectData = json.decode(projectJson)
            local project = ProjectModel:new(projectData, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local compiledSource = ProjectCompiler.compileRuntimeWithClosure(runtime)
            table.insert(compiledSources, compiledSource)
        end

        -- Verify all compilations produced identical output
        expect(compiledSources[1]).to.equal(compiledSources[2])
        expect(compiledSources[2]).to.equal(compiledSources[3])
    end)

    it("should produce stable output with custom procedures", function()
        -- Create a project with multiple procedures (warp/non-warp variants)
        local projectJson = [[{
            "targets": [{
                "isStage": false,
                "name": "Sprite1",
                "variables": {},
                "lists": {},
                "broadcasts": {},
                "blocks": {
                    "proc_proto_a": {
                        "opcode": "procedures_prototype",
                        "next": null,
                        "parent": "proc_def_a",
                        "inputs": {},
                        "fields": {},
                        "shadow": true,
                        "topLevel": false,
                        "mutation": {
                            "tagName": "mutation",
                            "children": [],
                            "proccode": "procedure_a",
                            "argumentids": "[]",
                            "argumentnames": "[]",
                            "argumentdefaults": "[]",
                            "warp": "false"
                        }
                    },
                    "proc_def_a": {
                        "opcode": "procedures_definition",
                        "next": null,
                        "parent": null,
                        "inputs": {
                            "custom_block": [1, "proc_proto_a"]
                        },
                        "fields": {},
                        "shadow": false,
                        "topLevel": true
                    },
                    "proc_proto_b": {
                        "opcode": "procedures_prototype",
                        "next": null,
                        "parent": "proc_def_b",
                        "inputs": {},
                        "fields": {},
                        "shadow": true,
                        "topLevel": false,
                        "mutation": {
                            "tagName": "mutation",
                            "children": [],
                            "proccode": "procedure_b",
                            "argumentids": "[]",
                            "argumentnames": "[]",
                            "argumentdefaults": "[]",
                            "warp": "true"
                        }
                    },
                    "proc_def_b": {
                        "opcode": "procedures_definition",
                        "next": null,
                        "parent": null,
                        "inputs": {
                            "custom_block": [1, "proc_proto_b"]
                        },
                        "fields": {},
                        "shadow": false,
                        "topLevel": true
                    },
                    "hat1": {
                        "opcode": "event_whenflagclicked",
                        "next": "call_a",
                        "parent": null,
                        "inputs": {},
                        "fields": {},
                        "shadow": false,
                        "topLevel": true
                    },
                    "call_a": {
                        "opcode": "procedures_call",
                        "next": "call_b",
                        "parent": "hat1",
                        "inputs": {},
                        "fields": {},
                        "shadow": false,
                        "topLevel": false,
                        "mutation": {
                            "tagName": "mutation",
                            "children": [],
                            "proccode": "procedure_a",
                            "argumentids": "[]",
                            "warp": "false"
                        }
                    },
                    "call_b": {
                        "opcode": "procedures_call",
                        "next": null,
                        "parent": "call_a",
                        "inputs": {},
                        "fields": {},
                        "shadow": false,
                        "topLevel": false,
                        "mutation": {
                            "tagName": "mutation",
                            "children": [],
                            "proccode": "procedure_b",
                            "argumentids": "[]",
                            "warp": "true"
                        }
                    }
                },
                "costumes": [{
                    "name": "costume1",
                    "bitmapResolution": 1,
                    "dataFormat": "svg",
                    "assetId": "test",
                    "md5ext": "test.svg",
                    "rotationCenterX": 48,
                    "rotationCenterY": 50
                }],
                "sounds": [],
                "volume": 100,
                "visible": true,
                "x": 0,
                "y": 0,
                "size": 100,
                "direction": 90,
                "draggable": false,
                "rotationStyle": "all around"
            }, {
                "isStage": true,
                "name": "Stage",
                "variables": {},
                "lists": {},
                "broadcasts": {},
                "blocks": {},
                "costumes": [],
                "sounds": [],
                "volume": 100
            }],
            "meta": {}
        }]]

        local compiledSources = {}

        -- Compile the same project 3 times
        for i = 1, 3 do
            local projectData = json.decode(projectJson)
            local project = ProjectModel:new(projectData, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local compiledSource = ProjectCompiler.compileRuntimeWithClosure(runtime)
            table.insert(compiledSources, compiledSource)
        end

        -- Verify all compilations produced identical output
        expect(compiledSources[1]).to.equal(compiledSources[2])
        expect(compiledSources[2]).to.equal(compiledSources[3])
    end)

    it("should preserve block order from JSON", function()
        -- Create project with specific block order
        local projectJson = [[{
            "targets": [{
                "isStage": true,
                "name": "Stage",
                "variables": {},
                "lists": {},
                "broadcasts": {},
                "blocks": {
                    "z_block": {
                        "opcode": "event_whenflagclicked",
                        "next": null,
                        "parent": null,
                        "inputs": {},
                        "fields": {},
                        "shadow": false,
                        "topLevel": true
                    },
                    "a_block": {
                        "opcode": "event_whenkeypressed",
                        "next": null,
                        "parent": null,
                        "inputs": {},
                        "fields": {
                            "KEY_OPTION": ["space", null]
                        },
                        "shadow": false,
                        "topLevel": true
                    }
                },
                "costumes": [],
                "sounds": [],
                "currentCostume": 0,
                "volume": 100
            }],
            "meta": {}
        }]]

        local projectData = json.decode(projectJson)
        local project = ProjectModel:new(projectData, {})

        -- Verify blockOrder preserves JSON order (not alphabetical)
        local stage = project.targets[1]
        expect(#stage.blockOrder).to.equal(2)
        expect(stage.blockOrder[1]).to.equal("z_block")  -- First in JSON
        expect(stage.blockOrder[2]).to.equal("a_block")  -- Second in JSON
    end)
end)
