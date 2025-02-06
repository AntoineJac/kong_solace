local solaceLib = require("kong.plugins.debug-logging.solaceLib")

local plugin = {
  PRIORITY = 15, -- Set the plugin priority to determine execution order
  VERSION = "0.1", -- Plugin version in X.Y.Z format
}

-- Runs in the 'access' phase
function plugin:access(plugin_conf)

    -- Example of usage
  local err = solaceLib.initialize()
  if err then
    print(err)
    return
  end

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
