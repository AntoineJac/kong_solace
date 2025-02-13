local solaceLib = {}

local ffi = require "ffi"

local SolaceKongLib = nil
local libsolaceName = "libsolclient.so"  -- Adjust the name of your library

ffi.cdef[[
    typedef void* solClient_opaqueSession_pt;
    typedef void* solClient_opaqueMsg_pt;
    typedef void* solClient_opaqueContext_pt;

    const char* solClient_session_eventToString(int sessionEvent);

    typedef struct solClient_session_eventCallbackInfo {
        const char *sessionEvent;
        const char *responseCode;
        const char *info_p;
        void *correlation_p;
    } solClient_session_eventCallbackInfo_t, *solClient_session_eventCallbackInfo_pt;

    typedef int (*solClient_session_rxMsgCallbackFunc_t)(solClient_opaqueSession_pt session_p, solClient_opaqueMsg_pt msg_p, void* user_p);
    typedef void (*solClient_session_eventCallbackFunc_t)(solClient_opaqueSession_pt session_p, solClient_session_eventCallbackInfo_pt eventInfo_p, void* user_p);

    typedef int (*solClient_context_registerFdFunc_t)(void *app_p, int fd, int events, void *callback_p, void *user_p);
    typedef int (*solClient_context_unregisterFdFunc_t)(void *app_p, int fd);

    typedef struct solClient_context_createRegisterFdFuncInfo
    {
      solClient_context_registerFdFunc_t regFdFunc_p;
      solClient_context_unregisterFdFunc_t unregFdFunc_p;
      void *user_p;
    } solClient_context_createRegisterFdFuncInfo_t;

    typedef struct solClient_context_createFuncInfo
    {
      solClient_context_createRegisterFdFuncInfo_t regFdInfo;
    } solClient_context_createFuncInfo_t;

    typedef struct solClient_session_createEventCallbackFuncInfo {
      solClient_session_eventCallbackFunc_t callback_p;
      void *user_p;
    } solClient_session_createEventCallbackFuncInfo_t;

    typedef struct solClient_session_createRxMsgCallbackFuncInfo
    {
      solClient_session_rxMsgCallbackFunc_t callback_p;
      void *user_p;
    } solClient_session_createRxMsgCallbackFuncInfo_t;

    typedef struct solClient_session_createRxCallbackFuncInfo
    {
      void *callback_p;
      void *user_p;
    } solClient_session_createRxCallbackFuncInfo_t;

    typedef struct {
      solClient_session_createRxCallbackFuncInfo_t rxInfo;
      solClient_session_createEventCallbackFuncInfo_t eventInfo;
      solClient_session_createRxMsgCallbackFuncInfo_t rxMsgInfo;
    } solClient_session_createFuncInfo_t;

    typedef struct {
      int destType;
      const char* dest;
    } solClient_destination_t;
    
    int solClient_initialize(int logLevel, const char **props);
    int solClient_context_create(char **props, solClient_opaqueContext_pt *context_p, 
                                 solClient_context_createFuncInfo_t *funcInfo_p, size_t contextFuncInfoSize);
    int solClient_session_create(char **sessionProps, solClient_opaqueContext_pt context_p, 
                                 solClient_opaqueSession_pt *session_p, solClient_session_createFuncInfo_t *sessionFuncInfo, 
                                 size_t sessionFuncInfoSize);
    int solClient_session_connect(solClient_opaqueSession_pt session_p);
    int solClient_msg_setDestination(solClient_opaqueMsg_pt msg_p, solClient_destination_t *destination, size_t destinationSize);
    int solClient_msg_setAckImmediately(solClient_opaqueMsg_pt msg_p, bool val);
    int solClient_msg_setDeliveryMode(solClient_opaqueMsg_pt msg_p, int delivery_mode);
    int solClient_msg_setBinaryAttachment(solClient_opaqueMsg_pt msg_p, void *binaryAttachment, size_t attachmentSize);
    int solClient_session_sendMsg(solClient_opaqueSession_pt session_p, solClient_opaqueMsg_pt msg_p);
    int solClient_cleanup(void);
    int solClient_msg_alloc(solClient_opaqueMsg_pt *msg_p);
    int solClient_msg_free(solClient_opaqueMsg_pt *msg_p);
    int solClient_session_destroy (solClient_opaqueSession_pt * session_p);
    int solClient_log_setFilterLevel (int category, int level);
]]


-- Function to load Solace shared library
function solaceLib.loadSolaceLibrary()
  local loaded, err = pcall(ffi.load, libsolaceName)
  if not loaded then
    return nil, "Unable to load the Solace library: " .. err
  end

  SolaceKongLib = ffi.load(libsolaceName)

  return true
end

-- Initialize the Solace API
function solaceLib.initialize()
  local sdk_log_level = 0 -- default for initialization could be configured in config
  -- we keep the default global configuration properties
  local rc = SolaceKongLib.solClient_initialize(sdk_log_level, nil)
  if rc ~= 0 then
    return nil, "issue when initlalizing the lib, code: " .. rc
  end

  return true
end

-- Edit the Solace SDK Log level
function solaceLib.solClient_log_setFilterLevel(sdk_log_level)
  local sdk_log_level = sdk_log_level or 0
   -- only allow log level change and keep logging for all categories
  local rc = SolaceKongLib.solClient_log_setFilterLevel(0, sdk_log_level)
  if rc ~= 0 then
    return nil, "issue when changing the lib log level, code: " .. rc
  end

  return true
end

-- Define a default callback for receiving messages (empty function)
local function sessionMessageReceiveCallback(session_p, msg_p, user_p)
  print("SessionMessageReceiveCallback")

  return 0
end

-- Define a session event callback function
local function sessionEventCallback(session_p, eventInfo_p, user_p)
  -- use print as kong.log not ready for initialization event
  print("SessionEventCallback")

  if eventInfo_p and eventInfo_p ~= ffi.NULL then
    local sessionEvent = eventInfo_p.sessionEvent
    if sessionEvent and sessionEvent ~= ffi.NULL then
      sessionEvent = tonumber(ffi.cast("intptr_t", sessionEvent))
    else
      sessionEvent = 0
    end
    
    if sessionEvent == 6 then
      kong.ctx.shared.ack_received = true
    end

    if sessionEvent == 0 then
      -- we use a blocking connection so no need to use the up event
    end

    if sessionEvent == 1 then
      local session_id = ngx.md5(tostring(session_p))
      -- mandatory to delete session outside of the callback to avoid malloc
      kong.worker_events.post_local("solaceFunction", "delete", session_id)
    end

    print("Session event: ", sessionEvent)

    local responseCode = eventInfo_p.responseCode
    print("Response Code: ", responseCode[0])
  end
end


-- Create a session context
function solaceLib.createContext()
  -- Define the context properties array (this corresponds to SOLCLIENT_CONTEXT_PROPS_DEFAULT_WITH_CREATE_THREAD in C)
  local SOLCLIENT_CONTEXT_PROPS_DEFAULT_WITH_CREATE_THREAD = ffi.new("char*[15]")

  -- Default context properties (replicating values in C code)
  -- Context is not configurable by customer as it used complex threading logic
  SOLCLIENT_CONTEXT_PROPS_DEFAULT_WITH_CREATE_THREAD[0] = ffi.cast("char*", "CONTEXT_TIME_RES_MS")
  SOLCLIENT_CONTEXT_PROPS_DEFAULT_WITH_CREATE_THREAD[1] = ffi.cast("char*", "50")

  SOLCLIENT_CONTEXT_PROPS_DEFAULT_WITH_CREATE_THREAD[2] = ffi.cast("char*", "CONTEXT_CREATE_THREAD")
  SOLCLIENT_CONTEXT_PROPS_DEFAULT_WITH_CREATE_THREAD[3] = ffi.cast("char*", "1") -- this is mandatory for running in Kong

  SOLCLIENT_CONTEXT_PROPS_DEFAULT_WITH_CREATE_THREAD[4] = ffi.cast("char*", "CONTEXT_THREAD_AFFINITY")
  SOLCLIENT_CONTEXT_PROPS_DEFAULT_WITH_CREATE_THREAD[5] = ffi.cast("char*", "0") -- keep Kong affinity

  SOLCLIENT_CONTEXT_PROPS_DEFAULT_WITH_CREATE_THREAD[6] = ffi.cast("char*", "CONTEXT_THREAD_AFFINITY_CPU_LIST")
  SOLCLIENT_CONTEXT_PROPS_DEFAULT_WITH_CREATE_THREAD[7] = ffi.cast("char*", "0") -- keep Kong affinity


  -- Create context
  local context_p = ffi.new("solClient_opaqueContext_pt[1]")
  local contextFuncInfo = ffi.new("solClient_context_createFuncInfo_t")
  contextFuncInfo.regFdInfo.regFdFunc_p = nil
  contextFuncInfo.regFdInfo.unregFdFunc_p = nil
  contextFuncInfo.regFdInfo.user_p = nil
  
  local rc = SolaceKongLib.solClient_context_create(SOLCLIENT_CONTEXT_PROPS_DEFAULT_WITH_CREATE_THREAD, context_p, contextFuncInfo, ffi.sizeof(contextFuncInfo))
  if rc ~= 0 then
    return nil, "Failed to create context, code: " .. rc
  end

  -- Optionally check if context pointer is valid (not NULL)
  if context_p[0] == ffi.NULL then
    return nil, "Context pointer is NULL"
  end

  return context_p
end

-- Create a session context
function solaceLib.createSession(context_p, config)

  -- Create session
  local session_p = ffi.new("solClient_opaqueSession_pt[1]")
  local sessionFuncInfo = ffi.new("solClient_session_createFuncInfo_t")

  -- Get max session properties + add 2 for the first and last nil bytes
  local number_session_properties = (#config.solace_sessions_properties * 2) + (9 * 2) + 2

  -- Create session properties
  local sessionProps = ffi.new("char*[" .. number_session_properties .. "]")
  
  -- Initialize first nil byte
  sessionProps[0] = ffi.cast("char*", nil)

  -- Default session properties
  sessionProps[1] = ffi.cast("char*", "SESSION_HOST")
  sessionProps[2] = ffi.cast("char*", config.session_host)

  sessionProps[3] = ffi.cast("char*", "SESSION_CONNECT_BLOCKING")
  sessionProps[4] = ffi.cast("char*", "1")

  sessionProps[5] = ffi.cast("char*", "SESSION_CONNECT_TIMEOUT_MS")
  sessionProps[6] = ffi.cast("char*", config.session_connect_timeout_ms)

  sessionProps[7] = ffi.cast("char*", "SESSION_SEND_BLOCKING")
  sessionProps[8] = ffi.cast("char*", "1")

  sessionProps[9] = ffi.cast("char*", "SESSION_WRITE_TIMEOUT_MS")
  sessionProps[10] = ffi.cast("char*", config.session_write_timeout_ms)

  -- Start with position 11 for optional properties
  local position = 11

  -- Add optional session properties
  if config.session_vpn_name then
    sessionProps[position] = ffi.cast("char*", "SESSION_VPN_NAME")
    sessionProps[position + 1] = ffi.cast("char*", config.session_vpn_name)
    position = position + 2
end

  if config.session_authentication_scheme ~= "NONE" then
    sessionProps[position] = ffi.cast("char*", "SESSION_AUTHENTICATION_SCHEME")
    sessionProps[position + 1] = ffi.cast("char*", config.session_authentication_scheme)
    position = position + 2
    
    if config.session_authentication_scheme == "AUTHENTICATION_SCHEME_BASIC" then  
      sessionProps[position] = ffi.cast("char*", "SESSION_USERNAME")
      sessionProps[position + 1] = ffi.cast("char*", config.session_username)
      position = position + 2
  
      sessionProps[position] = ffi.cast("char*", "SESSION_PASSWORD")
      sessionProps[position + 1] = ffi.cast("char*", config.session_password)

      position = position + 2
    end

    if config.session_authentication_scheme == "AUTHENTICATION_SCHEME_OAUTH2" then  
      if config.session_oauth2_access_token then
        sessionProps[position] = ffi.cast("char*", "SESSION_OAUTH2_ACCESS_TOKEN")
        sessionProps[position +1] = ffi.cast("char*", config.session_oauth2_access_token)
        position = position + 2
      end

      if config.session_oidc_id_token then
        sessionProps[position] = ffi.cast("char*", "SESSION_OIDC_ID_TOKEN")
        sessionProps[position +1] = ffi.cast("char*", config.session_oidc_id_token)
        position = position + 2
      end
    end
  end

  -- Handle additional properties in solace_sessions_properties
  for i, property in ipairs(config.solace_sessions_properties) do
    sessionProps[position] = ffi.cast("char*", property.property_key)
    sessionProps[position + 1] = ffi.cast("char*", property.property_value)
    position = position + 2
  end

  -- End with the last nil byte
  sessionProps[position] = ffi.cast("char*", nil)

  -- Assign callbacks or leave as NULL
  sessionFuncInfo.rxMsgInfo.callback_p = sessionMessageReceiveCallback
  sessionFuncInfo.rxMsgInfo.user_p = nil

  sessionFuncInfo.eventInfo.callback_p = sessionEventCallback
  sessionFuncInfo.eventInfo.user_p = nil
  
  local rc = SolaceKongLib.solClient_session_create(sessionProps, context_p[0], session_p, sessionFuncInfo, ffi.sizeof(sessionFuncInfo))
  if rc ~= 0 then
    return nil, "Failed to create session, code: " .. rc
  end

  -- Check if the session pointer is valid
  if session_p[0] == ffi.NULL then
    return nil, "Session pointer is NULL"
  end

  return session_p
end


-- Create a session context
function solaceLib.connectSession(session_p)
  local rc = SolaceKongLib.solClient_session_connect(session_p[0])
  if rc ~= 0 then
    return nil, "Solace connection failed, code: " .. rc
  end

  return true
end

-- Create a session context
function solaceLib.sendMessage(session_p, config)
  local msg_p = ffi.new("solClient_opaqueMsg_pt[1]")

  local rc = SolaceKongLib.solClient_msg_alloc(msg_p)
  if rc ~= 0 then
    return nil, "solClient_msg_alloc failed, code: " .. rc
  end

  local delivery_mode
  -- Hexa so 0 for Direct, 16 for Persistent and 32 for Non Persistent
  if config.message_delivery_mode == "DIRECT" then
    delivery_mode = 0
  elseif config.message_delivery_mode == "PERSISTENT" then
    delivery_mode = 16
  elseif config.message_delivery_mode == "NONPERSISTENT" then
    delivery_mode = 32
  else
    return nil, "invalid delivery mode"
  end
  
  rc = SolaceKongLib.solClient_msg_setDeliveryMode(msg_p[0], delivery_mode)
  if rc ~= 0 then
    return nil, "solClient_msg_setDeliveryMode failed, code: " .. rc
  end

  local destination = ffi.new("solClient_destination_t")

  local destType
  if config.message_destination_type == "TOPIC" then 
    destType = 0
  elseif config.message_destination_type == "QUEUE" then
    destType = 1
  else
    return nil, "invalid destination type"
  end

  local destTypeCapturesPattern = "%$(uri_captures%[\"(.-)\"%])"
  -- Check if there are any captures in destType
  local capture_keys = {}
  for key in destType:gmatch(destTypeCapturesPattern) do
    table.insert(capture_keys, key)
  end

  -- Only proceed if we have any capture keys to replace
  if #capture_keys > 0 then
    -- Get the named captures from the URI
    local captures = kong.request.get_uri_captures()

    -- Replace all occurrences of the named captures in one pass
    for _, key in ipairs(capture_keys) do
      -- Check if the key exists in the captures
      if captures.named[key] then
        -- Replace all instances of the key with the corresponding capture value
        destType = destType:gsub(destTypeCapturesPattern:format(key), captures.named[key])
      end
    end
  end
  destination.destType = destType -- 0 for Topic and 1 for Queue

  local dest = config.message_destination_name -- Topic or Queue name
  destination.dest = ffi.cast("const char*", dest)

  -- Set the destination for the message
  rc = SolaceKongLib.solClient_msg_setDestination(msg_p[0], destination, ffi.sizeof(destination))
  if rc ~= 0 then
    return nil, "solClient_msg_setDestination failed, code: " .. rc
  end

  rc = SolaceKongLib.solClient_msg_setAckImmediately(msg_p[0], true)
  if rc ~= 0 then
    return nil, "solClient_msg_setAckImmediately failed, code: " .. rc
  end

  local message
  if config.message_content_type == "CUSTOM" then
    message = config.message_content_override
  else
    message = kong.request.get_raw_body()
  end

  if not message or message == "" then
    return nil, "no message available to send"
  end

  -- Convert the Lua string to a C-style string
  local binaryAttachment = ffi.new("char[?]", #message, message)

  SolaceKongLib.solClient_msg_setBinaryAttachment(msg_p[0], binaryAttachment, #message)
  if rc ~= 0 then
    return nil, "solClient_msg_setBinaryAttachment failed, code: " .. rc
  end

  rc = SolaceKongLib.solClient_session_sendMsg(session_p[0], msg_p[0])
  if rc ~= 0 then
    return nil, "solClient_session_sendMsg failed, code: " .. rc
  end

  solaceLib.solClient_msg_free()
  return true
end

-- Cleanup the Solace API
function solaceLib.solClient_msg_free()
  local rc = SolaceKongLib.solClient_cleanup()
  if rc ~= 0 then
    kong.log.err("solClient_msg_free failed, code: ", rc)
  end
end 

-- Cleanup the Solace API
function solaceLib.cleanup()
  local rc = SolaceKongLib.solClient_cleanup()
  if rc ~= 0 then
    return nil, "solClient_cleanup failed, code: " .. rc
  end
end

-- Cleanup the Solace Sessions
function solaceLib.solClient_session_destroy(session_p)
  local rc = SolaceKongLib.solClient_session_destroy(session_p)
  if rc ~= 0 then
    return nil, "solClient_session_destroy failed, code: " .. rc
  end
end

return solaceLib
