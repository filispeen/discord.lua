require("spec_helper")

local Paginator = require("./core/paginator")

describe("Paginator", function()
    it("lazily fetches cursor pages and honours the total limit", function()
        local calls = {}
        local pages = {
            [false] = { { id = "3" }, { id = "2" } },
            ["2"] = { { id = "1" } },
        }
        local paginator = Paginator.new(function(params)
            calls[#calls + 1] = params
            return pages[params.before or false]
        end, { page_size = 2, limit = 3 })

        local ids = {}
        for item in paginator:iter() do
            ids[#ids + 1] = item.id
        end

        assert.same({ "3", "2", "1" }, ids)
        assert.equals(2, #calls)
        assert.equals("2", calls[2].before)
        assert.equals(1, calls[2].limit)
    end)
end)
