local PerformanceDataHelper do
    PerformanceDataHelper = { }

    ffi.cdef(ffi.abi("64bit") and "typedef uint64_t DWORD_PTR;" or "typedef uint32_t DWORD_PTR;")
    ffi.cdef [[
        typedef uint32_t DWORD;
        typedef int32_t  PDH_FUNCTION;
        typedef void*    PDH_HQUERY;
        typedef void*    PDH_HCOUNTER;
        typedef uint16_t WCHAR;
        typedef const WCHAR* LPCWSTR;
        typedef WCHAR*   LPWSTR;
        typedef DWORD*   LPDWORD;

        typedef struct {
            DWORD CStatus;
            union {
                long        longValue;
                double      doubleValue;
                long long   largeValue;
                const char  *AnsiStringValue;
                const WCHAR *WideStringValue;
            };
        } PDH_FMT_COUNTERVALUE;

        typedef struct {
            LPWSTR szName;
            PDH_FMT_COUNTERVALUE FmtValue;
        } PDH_FMT_COUNTERVALUE_ITEM_W;

        PDH_FUNCTION PdhOpenQueryW(LPCWSTR szDataSource, DWORD_PTR dwUserData, PDH_HQUERY *phQuery);
        PDH_FUNCTION PdhAddEnglishCounterW(PDH_HQUERY hQuery, LPCWSTR szFullCounterPath, DWORD_PTR dwUserData, PDH_HCOUNTER *phCounter);
        PDH_FUNCTION PdhCollectQueryData(PDH_HQUERY hQuery);
        PDH_FUNCTION PdhGetFormattedCounterValue(PDH_HCOUNTER hCounter, DWORD dwFormat, LPDWORD lpdwType, PDH_FMT_COUNTERVALUE *pValue);
        PDH_FUNCTION PdhGetFormattedCounterArrayW(PDH_HCOUNTER hCounter, DWORD dwFormat, LPDWORD lpdwBufferSize, LPDWORD lpdwItemCount, PDH_FMT_COUNTERVALUE_ITEM_W *ItemBuffer);
        PDH_FUNCTION PdhCloseQuery(PDH_HQUERY hQuery);
    ]]

    local kernel32 = ffi.load "kernel32"
    local advapi32 = ffi.load "advapi32"
    local pdh = ffi.load "pdh"

    local FMT = bit.bor(0x00000200, 0x00008000)

    local function wide(s)
        local b = ffi.new("uint16_t[?]", #s + 1)

        for i = 1, #s do
            b[i - 1] = s:byte(i)
        end

        return b
    end

    local function name(ptr)
        local w, out, i = ffi.cast("uint16_t*", ptr), { }, 0

        while w[i] ~= 0 do
            out[#out + 1] = string.char(w[i] < 256 and w[i] or 63); i = i + 1
        end

        return table.concat(out)
    end

    local function read_value(counter, value_type)
        if not counter then
            return nil
        end

        local value = ffi.new("PDH_FMT_COUNTERVALUE")

        if pdh.PdhGetFormattedCounterValue(counter, FMT, nil, value) ~= 0 or value.CStatus ~= 0 then
            return nil
        end

        return value[value_type]
    end

    local function read_array(counter, value_type)
        local result = { }

        if not counter then
            return result
        end

        local size, count = ffi.new("DWORD[1]"), ffi.new("DWORD[1]")
        pdh.PdhGetFormattedCounterArrayW(counter, FMT, size, count, nil)

        if size[0] == 0 then
            return result
        end

        local buffer = ffi.new("uint8_t[?]", size[0])
        if pdh.PdhGetFormattedCounterArrayW(counter, FMT, size, count, ffi.cast("PDH_FMT_COUNTERVALUE_ITEM_W*", buffer)) ~= 0 then
            return result
        end

        local items = ffi.cast("PDH_FMT_COUNTERVALUE_ITEM_W*", buffer)
        for i = 0, count[0] - 1 do
            table.insert(result, {
                name = name(items[i].szName),
                value = items[i].FmtValue[value_type]
            })
        end

        return result
    end

    local counter_mt = { } do
        counter_mt.__index = counter_mt

        function counter_mt:new(counter)
            return setmetatable({
                counter = counter
            }, self)
        end

        function counter_mt:as_double()
            return read_value(self.counter, "doubleValue")
        end

        function counter_mt:as_long()
            return read_value(self.counter, "longValue")
        end

        function counter_mt:as_large()
            return read_value(self.counter, "largeValue")
        end

        function counter_mt:as_double_array()
            return read_array(self.counter, "doubleValue")
        end

        function counter_mt:as_long_array()
            return read_array(self.counter, "longValue")
        end

        function counter_mt:as_large_array()
            return read_array(self.counter, "largeValue")
        end
    end

    local query_mt = { } do
        query_mt.__index = query_mt

        function query_mt:new(query)
            return setmetatable({
                query = query
            }, self)
        end

        function query_mt:add_counter(path)
            local counter = ffi.new("PDH_HCOUNTER[1]")

            if pdh.PdhAddEnglishCounterW(self.query, wide(path), 0, counter) ~= 0 then
                return nil
            end

            return counter_mt:new(counter[0])
        end

        function query_mt:collect()
            pdh.PdhCollectQueryData(self.query)
        end

        function query_mt:close()
            pdh.PdhCloseQuery(self.query)
        end
    end

    function PerformanceDataHelper:open_query()
        local query = ffi.new("PDH_HQUERY[1]")

        if pdh.PdhOpenQueryW(nil, 0, query) ~= 0 then
            return nil
        end

        return query_mt:new(query[0])
    end
end

return PerformanceDataHelper