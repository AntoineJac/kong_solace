local plugin = {
  PRIORITY = 15, -- Set the plugin priority to determine execution order
  VERSION = "0.1", -- Plugin version in X.Y.Z format
}

local solaceLib = require("kong.plugins.debug-logging.solaceLib")

local sdk_initialized = false
local solaceSessions = {}
local solaceContext = nil


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
  
  -- Pass the necessary properties to create context
  -- One context for all workers - maybe one by worker in future
  if not solaceContext then
    kong.log.err("CONTEXT CREATED")
    solaceContext, err = solaceLib.createContext()
    if err then
      return "issue when creating context, code: " .. err
    end
  end

  local max_pool = 2

  -- Should we create a real session and lock process
  for i = 1, max_pool do
    kong.log.err("SESSION CREATION")
    local session_new, err = solaceLib.createSession(solaceContext)
    if err then
      kong.log.err("SESSION CREATION FAILED")
    end

    kong.log.err("SESSION CONNECTION")
    -- Connect to the session
    local ok, err = solaceLib.connectSession(session_new)
    if err then
      -- Destroy the session directly as no need to wait
      local _, err = solaceLib.solClient_session_destroy(session_new)
      if err then
        kong.log.err("Issue when cleaning session ", i, ", error: ", err)
      end

      kong.log.err("SESSION CONNECTION FAILED")
    end

    if ok then
      kong.log.err("SESSION CONNECTED TO SOLACE")
    end

    table.insert(solaceSessions, session_new)
  end

  -- maybe create on context by ngx.worker.id()
end

-- Runs in the 'access' phase
function plugin:configure()
  if not sdk_initialized then
    return
  end

  -- Clean up the Solace sessions
  for i, session in ipairs(solaceSessions) do
    -- Spawn a new thread to clean up the session
    ngx.thread.spawn(function()
      ngx.sleep(1) -- wait one second before destroying the session
      
      -- Destroy the session
      local _, err = solaceLib.solClient_session_destroy(session)
      if err then
        kong.log.err("Issue when cleaning session ", i, ", error: ", err)
      end

      kong.log.err("SESSION DESTROYED")
      
      -- Remove the session from the solaceSessions list
      table.remove(solaceSessions, i)
    end)
  end

end

-- Runs in the 'access' phase
function plugin:access(plugin_conf)
  if not sdk_initialized then
    return
  end

  kong.ctx.shared.ack_received = false
  local max_pool = 2

  -- Should we create a real session and lock process
  if #solaceSessions < max_pool then
    kong.log.err("SESSION CREATION")
    local session_new, err = solaceLib.createSession(solaceContext)
    if err then
      kong.response.exit(500, "Issue when creating the session with err: " .. err)
    end

    kong.log.err("SESSION CONNECTION")
    -- Connect to the session
    local ok, err = solaceLib.connectSession(session_new)
    if err then
      -- Destroy the session directly as no need to wait
      local _, err = solaceLib.solClient_session_destroy(session_new)
      if err then
        kong.log.err("Issue when cleaning session ", i, ", error: ", err)
      end

      kong.response.exit(500, "Issue when connecting the sessions")
    end

    if ok then
      kong.log.err("SESSION CONNECTED TO SOLACE")
    end

    table.insert(solaceSessions, session_new)
  end

  local random_index = math.random(#solaceSessions)
  local session_p = solaceSessions[random_index]
  kong.log.err("PICKED SESSION ", random_index)

  -- Pass the necessary properties and send the message
  local ok, err = solaceLib.sendMessage(session_p)
  if err then
    kong.response.exit(500, "Issue when sending the message with err: " .. err)
  end

  if not ok then
    kong.response.exit(500, "Message no sent within the send window")
  end

  
  local start_time = math.floor(ngx.now())
  local max_wait_time = 1.5

  while (math.floor(ngx.now()) - start_time) < max_wait_time do
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

  -- -- solaceLib.cleanup()
  -- local ok, err = solaceLib.cleanup()
  -- if err then
  --   kong.log.err(err)
  --   return
  -- end

  -- if ok then
  --   print("Cleanup complete!")
  -- end
end


-- Return the plugin object
return plugin
