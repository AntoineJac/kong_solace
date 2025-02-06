local plugin = {
  PRIORITY = 15, -- Set the plugin priority to determine execution order
  VERSION = "0.1", -- Plugin version in X.Y.Z format
}


local solaceLib = require("kong.plugins.debug-logging.solaceLib")

-- Runs in the 'access' phase
function plugin:init_worker() 

  -- Example of usage
  local err = solaceLib.initialize()
  if err then
    print(err)
    return
  end

end

-- Runs in the 'access' phase
function plugin:access(plugin_conf)

  -- Pass the necessary properties to create session and context
  local session_p, context_p, err = solaceLib.createSessionAndConnect("tcp://localhost:55554", "default", "default", "default")
  if err then
    print(err)
    return
  end

  print("Connected to Solace!")

  -- solaceLib.sendMessage(session_p)

  solaceLib.cleanup()
  print("Cleanup complete.")
  end


-- Return the plugin object
return plugin
