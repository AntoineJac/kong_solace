local solaceLib = {}

local ffi = require "ffi"

local SolaceKongLib = nil
local libsolaceName = "libsolclient.so"  -- Adjust the name of your library

ffi.cdef[[
    typedef void* solClient_opaqueSession_pt;
    typedef void* solClient_opaqueMsg_pt;
    typedef void* solClient_session_eventCallbackInfo_pt;
    typedef void* solClient_opaqueContext_pt;

    typedef int (*solClient_rxMsgCallback)(solClient_opaqueSession_pt session_p, solClient_opaqueMsg_pt msg_p, void* user_p);
    typedef void (*solClient_sessionEventCallback)(solClient_opaqueSession_pt session_p, solClient_session_eventCallbackInfo_pt eventInfo_p, void* user_p);

    typedef struct {
      void *field1;
      void *field2;
      void *field3;
    } solClient_context_createFuncInfo_t;

    typedef struct {
      void *callback_p;
      void *user_p;
  } solClient_callbackFuncInfo_t;

    typedef struct {
      solClient_callbackFuncInfo_t rxInfo;
      solClient_callbackFuncInfo_t eventInfo;
      solClient_callbackFuncInfo_t rxMsgInfo;
    } solClient_session_createFuncInfo_t;

    typedef struct {
      int destType;
      const char* dest;
    } solClient_destination_t;
    
    int solClient_initialize(int logLevel, const char *logFile);
    int solClient_context_create(int createThreadFlags, solClient_opaqueContext_pt *context_p, 
                                 void *contextFuncInfo, size_t contextFuncInfoSize);
    int solClient_session_create(char **sessionProps, solClient_opaqueContext_pt context_p, 
                                 solClient_opaqueSession_pt *session_p, void *sessionFuncInfo, 
                                 size_t sessionFuncInfoSize);
    int solClient_session_connect(solClient_opaqueSession_pt session_p);
    int solClient_msg_setDestination(solClient_opaqueMsg_pt msg_p, solClient_destination_t destination, size_t destinationSize);
    int solClient_msg_setDeliveryMode(solClient_opaqueMsg_pt msg_p, int delivery_mode);
    int solClient_msg_setBinaryAttachment(solClient_opaqueMsg_pt msg_p, void *binaryAttachment, size_t attachmentSize);
    int solClient_session_sendMsg(solClient_opaqueSession_pt session_p, solClient_opaqueMsg_pt msg_p);
    int solClient_cleanup(void);
    void solClient_msg_alloc(solClient_opaqueMsg_pt *msg_p);
    void solClient_msg_free(solClient_opaqueMsg_pt *msg_p);
]]

-- Function to load Solace shared library
function solaceLib.loadSolaceLibrary()
  local loaded, err = pcall(ffi.load, libsolaceName)
  if not loaded then
    return "Unable to load the Solace library: " .. err
  end
  SolaceKongLib = ffi.load(libsolaceName)
  return nil  -- Successfully loaded
end

-- Initialize the Solace API
function solaceLib.initialize()
  local err = solaceLib.loadSolaceLibrary()
  if err then
    return err
  end
  SolaceKongLib.solClient_initialize(7, nil)  -- Assuming 0 is the log level for default
  return nil
end

-- Create a session context
function solaceLib.createSessionAndConnect(host, vpn, username, password)

  
  -- Create context
  local context_p = ffi.new("solClient_opaqueContext_pt[1]")
  
  local contextFuncInfo = ffi.new("solClient_context_createFuncInfo_t")

  local rc = SolaceKongLib.solClient_context_create(0, context_p, contextFuncInfo, ffi.sizeof(contextFuncInfo))
  if rc ~= 0 then
    return nil, "Failed to create context"
  end

  -- Optionally check if context pointer is valid (not NULL)
  if context_p[0] == ffi.NULL then
    return nil, "Context pointer is NULL"
  end

  -- Create session properties
  local sessionProps = ffi.new("char*[20]")

  -- Set each property to point to a C string
  sessionProps[0] = ffi.cast("char*", nil)
  sessionProps[0] = ffi.cast("char*", "SESSION_HOST")
  sessionProps[1] = ffi.cast("char*", "tcp://host.docker.internal:55554")
  sessionProps[2] = ffi.cast("char*", "SESSION_VPN_NAME")
  sessionProps[3] = ffi.cast("char*", "default")
  sessionProps[4] = ffi.cast("char*", "SESSION_USERNAME")
  sessionProps[5] = ffi.cast("char*", "admin")
  sessionProps[6] = ffi.cast("char*", "SESSION_PASSWORD")
  sessionProps[7] = ffi.cast("char*", "admin")
  sessionProps[8] = ffi.cast("char*", "SESSION_CONNECT_TIMEOUT_MS")
  sessionProps[9] = ffi.cast("char*", "3000")

  sessionProps[10] = ffi.cast("char*", "SESSION_CONNECT_BLOCKING")
  sessionProps[11] = ffi.cast("char*", "1")

  sessionProps[12] = ffi.cast("char*", "SESSION_BLOCK_WHILE_CONNECTING")
  sessionProps[13] = ffi.cast("char*", "1")

  sessionProps[14] = ffi.cast("char*", nil)
  

  -- Create session
  local session_p = ffi.new("solClient_opaqueSession_pt[1]")

  -- Define a default callback for receiving messages (empty function)
  local function sessionMessageReceiveCallback(session_p, msg_p, user_p)
    -- Implement the callback functionality if needed
    return 0 -- Return the appropriate return code
  end

  -- Define a session event callback function
  local function sessionEventCallback(session_p, eventInfo_p, user_p)
    -- Handle session events here
    return
  end

  -- Create C function pointers for the Lua callbacks
  local messageReceiveCallback = ffi.cast("solClient_rxMsgCallback", sessionMessageReceiveCallback)
  local sessionEventCallbackPtr = ffi.cast("solClient_sessionEventCallback", sessionEventCallback)
  
  -- Set session function info with callbacks
  local sessionFuncInfo = ffi.new("solClient_session_createFuncInfo_t")

  -- Assign callbacks or leave as NULL
  sessionFuncInfo.rxMsgInfo.callback_p = messageReceiveCallback
  sessionFuncInfo.rxMsgInfo.user_p = nil

  sessionFuncInfo.eventInfo.callback_p = sessionEventCallbackPtr
  sessionFuncInfo.eventInfo.user_p = nil
  
  -- Create a helper function to convert error codes to human-readable error messages
  local function getSolaceErrorMessage(rc)
    if rc == 0 then
      return "Success"
    elseif rc == -1 then
      return "General failure"
    elseif rc == -2 then
      return "Invalid argument"
    -- Add other error codes as per the Solace API documentation
    else
      return "Unknown error code: " .. tostring(rc)
    end
  end

  kong.log.err("SessionFuncInfo size: " .. ffi.sizeof(sessionFuncInfo))
  kong.log.err("ContextFuncInfo size: " .. ffi.sizeof(contextFuncInfo))

  rc = SolaceKongLib.solClient_session_create(sessionProps, context_p[0], session_p, sessionFuncInfo, ffi.sizeof(sessionFuncInfo))
  if rc ~= 0 then
    local errorMsg = getSolaceErrorMessage(rc)
    kong.log.err("ANTOINE - Failed to create session. Error code: " .. tostring(rc) .. ", Error message: " .. errorMsg)
    return nil, "Failed to create session"
  end

  -- Check if the session pointer is valid
  if session_p[0] == ffi.NULL then
    return nil, "Session pointer is NULL"
  end

  -- Connect session
  rc = SolaceKongLib.solClient_session_connect(session_p[0])
  if rc ~= 0 then
    kong.log.err("ANTOINE issue with session: ", rc)
  end

  ngx.sleep(1)

  -- local process = assert(io.popen("export LD_LIBRARY_PATH=/usr/local/kong/solace/lib/linux/x64:$LD_LIBRARY_PATH && cd .. && cd bin && pwd && ls && ./TopicPublisher tcp://host.docker.internal:55554 default admin admin tutorial/topic", "r"))
  -- local output = process:read("*a")  -- Read full output
  -- process:close()

  return session_p, context_p, nil  -- Return session and context
end

-- Send a message
function solaceLib.sendMessage(session_p)
  if not session_p then
    return
  end

  local msg_p = ffi.new("solClient_opaqueMsg_pt[1]")
  SolaceKongLib.solClient_msg_alloc(msg_p)

  local delivery_mode = 1 -- SOLCLIENT_DELIVERY_MODE_DIRECT
  local delivery_result = SolaceKongLib.solClient_msg_setDeliveryMode(msg_p[0], delivery_mode)


  local destination = ffi.new("solClient_destination_t")
  destination.destType = 0
  destination.dest = ffi.cast("char*", "tutorial/topic")

  -- Set the destination for the message
  local set_dest_result = SolaceKongLib.solClient_msg_setDestination(msg_p[0], destination, ffi.sizeof(destination))

  local text_p = "Hello world!"

  -- Convert the Lua string to a C-style string
  local binaryAttachment = ffi.new("char[?]", #text_p, text_p)

  SolaceKongLib.solClient_msg_setBinaryAttachment(msg_p[0], binaryAttachment, #text_p)

  local test_success = SolaceKongLib.solClient_session_sendMsg(session_p[0], msg_p[0])

  SolaceKongLib.solClient_msg_free(msg_p)
end

-- Cleanup the Solace API
function solaceLib.cleanup()
  SolaceKongLib.solClient_cleanup()
end

return solaceLib
