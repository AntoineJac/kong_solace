local typedefs = require "kong.db.schema.typedefs"

local list_properties_forbidden = {
  "SESSION_USERNAME",
  "SESSION_PASSWORD",
  "SESSION_HOST",
  "SESSION_PORT",
  "SESSION_VPN_NAME",
  "SESSION_CONNECT_TIMEOUT_MS",
  "SESSION_CONNECT_BLOCKING"
}

local PLUGIN_NAME = "debug-logging"


-- local function validate_properties(list_properties_forbidden)
--   for _, property in ipairs(properties) do
--     if not properties in list_properties then
--       return false, "Invalid property: " .. property
--     end
--   end

--   return true
-- end


local schema = {
  name = PLUGIN_NAME,
  fields = {
    { consumer = typedefs.no_consumer },
    { consumer_group = typedefs.no_consumer_group },
    { protocols = typedefs.protocols_http },
    { config = {
        -- The 'config' record is the custom part of the plugin schema
        type = "record",
        fields = {
          {
            solace_sessions_propertires = {
              description = "the Solace session properties",
              type = "array",
              elements = { type = "string" },
              -- custom_validator = validate_sessions_properties,
            },
          },
          {
            log_scope = {
              description = "Display the scope of the bearer token in the logs",
              required = true,
              type = "boolean",
              default = false,
            },
          },
        },
      },
    },
  },
}

return schema
