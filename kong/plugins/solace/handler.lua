local plugin = {
  PRIORITY = 15, -- Set the plugin priority to determine execution order
  VERSION = "0.1", -- Plugin version in X.Y.Z format
}

local solaceLib = require("kong.plugins.solace.solaceLib")
local uuid      = require "kong.tools.uuid"
local nkeys     = require "table.nkeys"
local cjson     = require "cjson"
local sdk_initialized = false
local previous_sdk_log_level = 0
local previous_session_hash
kong.solaceSessions = {}
kong.solaceContext = nil
kong.solace_ack_received = {}

local isLoaded, err = solaceLib.loadSolaceLibrary()
if err then
  kong.log.alert(err)
end

-- Runs in the 'access' phase
function plugin:init_worker()
  if not isLoaded then
    return
  end

  local err
  sdk_initialized, err = solaceLib.initialize()
  if err then
    kong.log.err(err)
    return
  end

  kong.worker_events.register(function(session_id)
    -- Remove the session from the solaceSessions list first to avoid any new connection
    kong.solaceSessions[session_id] = nil
    kong.log.debug("SESSION REMOVED")

    -- wait one second before destroying the session to handle current requests
    -- could use a worker event solClient_session_disconnect in future
    ngx.sleep(1)

    local _, err = solaceLib.solClient_session_destroy(kong.solaceSessions[session_id])
    if err then
      kong.log.err("Issue when cleaning session ", session_id, ", error: ", err)
    end
    kong.log.debug("SESSION DESTROYED")
  end, "solaceFunction", "delete")
  
  -- Pass the necessary properties to create context
  -- One context for all workers - maybe one by worker in future
  if not kong.solaceContext then
    kong.log.debug("CONTEXT CREATED")
    kong.solaceContext, err = solaceLib.createContext()
    if err then
      return "issue when creating context, code: " .. err
    end
  end

  -- maybe create on context by ngx.worker.id()
end

-- Runs in the 'access' phase
function plugin:configure(configs)
  if not sdk_initialized then
    return
  end
  
  local CONFIG = configs and configs[1] or nil

  -- Remove session when plugin is disabled or removed
  if not CONFIG then
    CONFIG = {
      solace_sdk_log_level = previous_sdk_log_level,
      solace_session_pool = 0
    }
  end

  -- check if require changing log level
  local sdk_log_level = CONFIG.solace_sdk_log_level
  if sdk_log_level ~= previous_sdk_log_level then
    kong.log.debug("LOG LEVEL CHANGED, previous: ", previous_sdk_log_level, " ,new: ", sdk_log_level)

    local _, err = solaceLib.solClient_log_setFilterLevel(sdk_log_level)
    if err then
      kong.log.err("Issue when changing the log level, error: ", err)
    end
    previous_sdk_log_level = sdk_log_level
  end

  -- clean sessions only if session fields changed
  local session_configs = {
    solace_sessions_properties = CONFIG.solace_sessions_properties,
    session_authentication_scheme = CONFIG.session_authentication_scheme,
    session_oauth2_access_token = CONFIG.session_oauth2_access_token,
    session_oidc_id_token = CONFIG.session_oidc_id_token,
    session_username = CONFIG.session_username,
    session_password = CONFIG.session_password,
    session_vpn_name = CONFIG.session_vpn_name,
    session_host = CONFIG.session_host,
    session_connect_timeout_ms = CONFIG.session_connect_timeout_ms,
    session_write_timeout_ms = CONFIG.session_write_timeout_ms,
    solace_session_pool = CONFIG.solace_session_pool
  }

  session_configs = cjson.encode(session_configs)
  local session_hash = ngx.md5(session_configs)

  if session_hash == previous_session_hash then
    return
  end
  previous_session_hash = session_hash

  -- Clean up the Solace sessions
  for session_id, session_p in pairs(kong.solaceSessions) do
    -- Spawn a new thread to clean up the session
    ngx.thread.spawn(function()
      -- Remove the session from the solaceSessions list first to avoid any new connection
      kong.solaceSessions[session_id] = nil
      kong.log.debug("SESSION REMOVED")

      -- wait one second before destroying the session to handle current requests
      -- could use a worker event solClient_session_disconnect in future
      ngx.sleep(1)
      
      -- Destroy the session
      local _, err = solaceLib.solClient_session_destroy(session_p)
      if err then
        kong.log.err("Issue when cleaning session ", session_id, ", error: ", err)
      end

      kong.log.debug("SESSION DESTROYED")
    end)
  end

  local session_pool = CONFIG.solace_session_pool
  -- Create sessions to match require session pool
  for i = 1, session_pool do
    kong.log.debug("SESSION CREATION")
    -- create session is blocking so no need to use a lock
    local session_new, err = solaceLib.createSession(kong.solaceContext, CONFIG)
    if err then
      kong.log.err("SESSION CREATION FAILED")
    end

    kong.log.debug("SESSION CONNECTION")
    -- Connect to the session
    local _, err = solaceLib.connectSession(session_new)
    if err then
      -- Destroy the session directly as no need to wait
      local _, err = solaceLib.solClient_session_destroy(session_new)
      if err then
        kong.log.err("Issue when cleaning session ", i, ", error: ", err)
      end

      kong.log.err("SESSION CONNECTION FAILED")
      return
    end

    kong.log.debug("SESSION CONNECTED TO SOLACE NEW")

    local session_id = ngx.md5(tostring(session_new[0]))
    kong.solaceSessions[session_id] = session_new
  end
end

-- Runs in the 'access' phase
function plugin:access(plugin_conf)
  if not sdk_initialized then
    return
  end

  kong.log.debug("NUMBER OF SESSION ", nkeys(kong.solaceSessions))

  local session_pool = plugin_conf.solace_session_pool
  -- Create sessions to match require session pool
  if nkeys(kong.solaceSessions) < session_pool then
    kong.log.debug("SESSION CREATION")
    -- create session is blocking so no need to use a lock
    local session_new, err = solaceLib.createSession(kong.solaceContext, plugin_conf)
    if err then
      kong.response.exit(501, "Issue when creating the session with err: " .. err)
    end

    kong.log.debug("SESSION CONNECTION")
    -- Connect to the session
    local _, err = solaceLib.connectSession(session_new)
    if err then
      -- Destroy the session directly as no need to wait
      local _, err = solaceLib.solClient_session_destroy(session_new)
      if err then
        kong.log.err("Issue when cleaning session ", i, ", error: ", err)
      end

      kong.response.exit(502, "Issue when connecting the sessions")
    end

    kong.log.debug("SESSION CONNECTED TO SOLACE")

    local session_id = ngx.md5(tostring(session_new[0]))
    kong.solaceSessions[session_id] = session_new
  end

  local connected_sessions = {}
  for session_id, session_p in pairs(kong.solaceSessions) do
    table.insert(connected_sessions, session_p)
  end

  if #connected_sessions == 0 then
    kong.response.exit(503, "No session available")
  end

  -- we use a random selector for the sessions
  -- The Solace SDK handle message buffering and queue sending, no lock logic require
  local random_index = math.random(#connected_sessions)
  local selected_session = connected_sessions[random_index]
  kong.log.debug("PICKED SESSION ", random_index)

  -- Create message id for ack event receipt
  local message_id = uuid.uuid()
  kong.solace_ack_received[message_id] = false

  -- Pass the necessary properties and send the message
  local _, err = solaceLib.sendMessage(selected_session, plugin_conf, message_id)
  -- important to collect garbage here to avoid memory leak
  collectgarbage()
  if err then
    kong.response.exit(504, "Issue when sending the message with err: " .. err)
  end

  if plugin_conf.message_delivery_mode == "DIRECT" then
    kong.response.exit(200, "Message sent as Direct so no Guaranteed delivery")
  end

  -- We use a loop as we need to empty solace_ack_received[message_id]
  -- While loop cause the solace_ack_received to be cleaned prematurely 
  local start_time = math.floor(ngx.now() * 1000)
  local max_wait_time = plugin_conf.ack_max_wait_time_ms
  local sleep_time = 100 --ms
  local max_iterations = math.floor(max_wait_time / sleep_time)

  -- We use a loop as while is not blocking and we need to empty solace_ack_received[message_id]
  for i = 1, max_iterations do
    if kong.solace_ack_received[message_id] == true then
      kong.solace_ack_received[message_id] = nil
      kong.response.exit(200, "Message has been sent to Solace 4")
    end
  
    -- Check if it is the last iteration
    if i == max_iterations then
      kong.solace_ack_received[message_id] = nil
    end
  
    ngx.sleep(sleep_time/1000)  -- Sleep for 0.1s to avoid CPU overload
  end
  
  kong.response.exit(505, "No callback received within the send window")
end

-- Runs in the 'access' phase
function plugin:log() 
  if not sdk_initialized then
    return
  end
end


-- Return the plugin object
return plugin
