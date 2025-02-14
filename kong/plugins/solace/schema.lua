local typedefs = require "kong.db.schema.typedefs"

local list_properties_forbidden = {
  "SESSION_AUTHENTICATION_SCHEME",
  "SESSION_USERNAME",
  "SESSION_PASSWORD",
  "SESSION_OAUTH2_ACCESS_TOKEN",
  "SESSION_OIDC_ID_TOKEN",
  "SESSION_HOST",
  "SESSION_VPN_NAME",
  "SESSION_CONNECT_TIMEOUT_MS",
  "SESSION_WRITE_TIMEOUT_MS",
  "SESSION_CONNECT_BLOCKING",
  "SESSION_SEND_BLOCKING",
  "SESSION_ACK_EVENT_MODE"
}

local PLUGIN_NAME = "solace"


local function is_empty(value)
  return value == nil or value == ngx.null or value == ""
end

local function validate_property_key(property)
  if not property.property_key:match("^SESSION_") then
    return false, "property key must start with 'SESSION_': " .. property.property_key
  end
  
  for _, forbidden_key in ipairs(list_properties_forbidden) do
    if property.property_key:match("^SOLCLIENT_SESSION") then
      return false, "use the macro value not name : " .. property.property_key
    end

    if property.property_key == forbidden_key then
      return false, "property forbidden: " .. property.property_key
    end
  end

  return true
end

local function validate_config(config)
  if config.session_authentication_scheme == "NONE" then
    return true
  end

  if config.session_authentication_scheme == "AUTHENTICATION_SCHEME_BASIC" then
    if is_empty(config.session_username) or is_empty(config.session_password) then
      return false, "for basic: auth session_username and session_password should be provided"
    end
  end

  if config.session_authentication_scheme == "AUTHENTICATION_SCHEME_OAUTH2" then
    if is_empty(config.session_oauth2_access_token) and is_empty(config.session_oidc_id_token) then
      return false, "for oauth2: one of session_oauth2_access_token or session_oidc_id_token should be provided"
    end

    if config.session_oauth2_access_token and config.session_oidc_id_token then
      return false, "only provide a unique session_oauth2_access_token or session_oidc_id_token"
    end
  end

  if config.message_content_type == "CUSTOM" then
    if is_empty(config.message_content_override) then
      return false, "content is mandatory for CUSTOM message content type"
    end
  end

  return true
end


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
            solace_sessions_properties = {
              description = "the Solace session properties",
              type = "array",
              len_max = 20,
              elements = {
                type = "record",
                required = false,
                fields = {
                  {
                    property_key = {
                      type = "string",
                      required = true,
                    },
                  },
                  {
                    property_value = {
                      type = "string",
                      required = true,
                      referenceable = false, -- maybe true in future
                    },
                  },
                },
                custom_validator = validate_property_key,
              },
            },
          },
          { 
            session_authentication_scheme = {
              description = "Indicates the authentication used by the session to connect with Solace.",
              required = true,
              type = "string",
              default = "AUTHENTICATION_SCHEME_BASIC", 
              one_of = { "NONE", "AUTHENTICATION_SCHEME_BASIC", "AUTHENTICATION_SCHEME_OAUTH2" },
            },
          },
          {
            session_oauth2_access_token = {
              type = "string",
              required = false,
              encrypted = true,
              referenceable = true,
            },
          },
          {
            session_oidc_id_token = {
              type = "string",
              required = false,
              encrypted = true,
              referenceable = true,
            },
          },
          {
            session_username = {
              type = "string",
              required = false,
            },
          },
          {
            session_password = {
              type = "string",
              required = false,
              encrypted = true,
              referenceable = true,
            },
          },
          {
            session_vpn_name = {
              type = "string",
              required = false,
            },
          },
          {
            session_host = typedefs.url({
              required = true,
              referenceable = true
            })
          },
          {
            session_connect_timeout_ms = {
              type = "integer",
              required = true,
              default = 3000,
              between = { 100, 10000 },
            },
          },
          {
            session_write_timeout_ms = {
              type = "integer",
              required = true,
              default = 3000,
              between = { 100, 10000 },
            },
          },
          {
            solace_session_pool = {
              type = "integer",
              required = true,
              between = { 0, 10 },
              default = 2,
            },
          },
          {
            message_delivery_mode = {
              type = "string",
              required = true,
              default = "DIRECT", 
              one_of = { "DIRECT", "PERSISTENT", "NONPERSISTENT" },
            },
          },
          {
            message_destination_type = {
              description = "You can use $(uri_captures['topic_name'] in this field",
              type = "string",
              required = true,
              default = "TOPIC", 
              one_of = { "TOPIC", "QUEUE" },
            },
          },
          {
            message_destination_name = {
              type = "string",
              required = true,
              default = "tutorial/topic",
            },
          },
          {
            message_content_type = {
              type = "string",
              required = true,
              default = "PAYLOAD", 
              one_of = { "PAYLOAD", "CUSTOM" },
            },
          },
          {
            message_content_override = {
              type = "string",
              required = false,
              default = "Hello World!",
            },
          },
          {
            ack_max_wait_time_ms = {
              type = "integer",
              required = true,
              default = 2000,
              between = { 100, 5000 },
            },
          },
          {
            solace_sdk_log_level = {
              type = "integer",
              required = true,
              default = 0,
              between = { 0, 7 },
            },
          },
        },
        custom_validator = validate_config,
      },
    },
  },
}

return schema
