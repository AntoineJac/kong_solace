local plugin = {
  PRIORITY = 15, -- Set the plugin priority to determine execution order
  VERSION = "0.1", -- Plugin version in X.Y.Z format
}

local solaceLib = require("kong.plugins.debug-logging.solaceLib")
local nkeys     = require "table.nkeys"
local sdk_initialized = false
local previous_session_hash, previous_sdk_log_level
kong.solaceSessions = {}
kong.solaceContext = nil

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
    -- Remove the session from the solaceSessions list
    kong.solaceSessions[session_id] = nil
    kong.log.err("SESSION REMOVED")

    -- wait one second before destroying the session to handle current requests
    -- could use a worker event solClient_session_disconnect in future
    ngx.sleep(1)

    local _, err = solaceLib.solClient_session_destroy(kong.solaceSessions[session_id])
    if err then
      kong.log.err("Issue when cleaning session ", session_id, ", error: ", err)
    end
    kong.log.err("SESSION DESTROYED")
  end, "solaceFunction", "delete")
  
  -- Pass the necessary properties to create context
  -- One context for all workers - maybe one by worker in future
  if not kong.solaceContext then
    kong.log.err("CONTEXT CREATED")
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

  -- to be changed with sessions config object
  local session_configs = CONFIG.log_scope
  local session_hash = ngx.md5(session_configs)

  if session_hash == previous_session_hash then
    return
  end
  previous_session_hash = session_hash

  -- check if require changing log level
  local sdk_log_level = CONFIG.solace_sdk_log_level
  if sdk_log_level ~= previous_sdk_log_level then
    local _, err = solaceLib.solClient_log_setFilterLevel(sdk_log_level)
    if err then
      kong.log.err("Issue when changing the log level, error: ", err)
    end
    previous_sdk_log_level = sdk_log_level
  end

  -- Clean up the Solace sessions
  for session_id, session_p in pairs(kong.solaceSessions) do
    -- Spawn a new thread to clean up the session
    ngx.thread.spawn(function()
      -- Remove the session from the solaceSessions list
      kong.solaceSessions[session_id] = nil
      kong.log.err("SESSION REMOVED")

      -- wait one second before destroying the session to handle current requests
      -- could use a worker event solClient_session_disconnect in future
      ngx.sleep(1)
      
      -- Destroy the session
      local _, err = solaceLib.solClient_session_destroy(session_p)
      if err then
        kong.log.err("Issue when cleaning session ", session_id, ", error: ", err)
      end

      kong.log.err("SESSION DESTROYED")
    end)
  end

  local session_pool = CONFIG.solace_session_pool

  -- Should we create a real session and lock process
  for i = 1, session_pool do
    kong.log.err("SESSION CREATION")
    local session_new, err = solaceLib.createSession(kong.solaceContext, CONFIG)
    if err then
      kong.log.err("SESSION CREATION FAILED")
    end

    kong.log.err("SESSION CONNECTION")
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

    kong.log.err("SESSION CONNECTED TO SOLACE NEW")

    local session_id = ngx.md5(tostring(session_new[0]))
    kong.solaceSessions[session_id] = session_new
  end

end

-- Runs in the 'access' phase
function plugin:access(plugin_conf)
  if not sdk_initialized then
    return
  end

  kong.ctx.shared.ack_received = false
  local session_pool = plugin_conf.solace_session_pool

  kong.log.err("NUMBER OF SESSION ", nkeys(kong.solaceSessions))

  -- Create sessions to match require session pool
  if nkeys(kong.solaceSessions) < session_pool then
    kong.log.err("SESSION CREATION")
    local session_new, err = solaceLib.createSession(kong.solaceContext, plugin_conf)
    if err then
      kong.response.exit(500, "Issue when creating the session with err: " .. err)
    end

    kong.log.err("SESSION CONNECTION")
    -- Connect to the session
    local _, err = solaceLib.connectSession(session_new)
    if err then
      -- Destroy the session directly as no need to wait
      local _, err = solaceLib.solClient_session_destroy(session_new)
      if err then
        kong.log.err("Issue when cleaning session ", i, ", error: ", err)
      end

      kong.response.exit(500, "Issue when connecting the sessions")
    end

    kong.log.err("SESSION CONNECTED TO SOLACE")

    local session_id = ngx.md5(tostring(session_new[0]))
    kong.solaceSessions[session_id] = session_new
  end

  local connected_sessions = {}
  for session_id, session_p in pairs(kong.solaceSessions) do
    table.insert(connected_sessions, session_p)
  end

  if #connected_sessions == 0 then
    kong.response.exit(500, "No session available")
  end

  local random_index = math.random(#connected_sessions)
  local selected_session = connected_sessions[random_index]
  kong.log.err("PICKED SESSION ", random_index)

  -- Pass the necessary properties and send the message
  local _, err = solaceLib.sendMessage(selected_session, plugin_conf)
  if err then
    solaceLib.solClient_msg_free() -- free malloc
    kong.response.exit(500, "Issue when sending the message with err: " .. err)
  end

  if plugin_conf.message_delivery_mode == "DIRECT" then
    kong.response.exit(200, "Message sent as Direct so no Guaranteed delivery")
  end

  local start_time = math.floor(ngx.now() * 1000)
  local max_wait_time = plugin_conf.ack_max_wait_time_ms

  while (math.floor(ngx.now() * 1000) - start_time) < max_wait_time do
    if kong.ctx.shared.ack_received == true then
        kong.response.exit(200, "Message has been sent to Solace")
    end

    ngx.sleep(0.1)  -- Sleep for 0.1s to avoid CPU overload
  end
  
  kong.response.exit(500, "Message no sent within the send window")
end

-- Runs in the 'access' phase
function plugin:log() 
  if not sdk_initialized then
    return
  end
end


-- Return the plugin object
return plugin
