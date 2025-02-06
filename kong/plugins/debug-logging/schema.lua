local typedefs = require "kong.db.schema.typedefs"


local PLUGIN_NAME = "debug-logging"


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
            log_string = {
              description = "add this into the log",
              required = true,
              type = "string",
              referenceable = true,
              default = "default_value",
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
          {
            log_client_id = {
              description = "Display the client id of the bearer token in the logs",
              required = true,
              type = "boolean",
              default = false,
            },
          },
          {
            log_request_body = {
              description = "Display the request body of the request in the logs",
              required = true,
              type = "boolean",
              default = false,
            },
          },
          {
            log_response_body = {
              description = "Display the response body of the request token in the logs",
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
