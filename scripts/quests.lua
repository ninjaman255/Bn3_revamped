local ezquests = require('scripts/ezlibs-scripts/ezquests')

ezquests.add_quest({
    name = "TEST",
    
    -- handle_event_async must return a promise (use async/await)
    handle_event_async = function(self, player_id, event_value)
        return async(function()
            print("[TEST Quest] event received:", event_value, "for player", player_id)
            
            if event_value == "accept" then
                -- Accept the quest
                ezquests.set_player_quest_flag(player_id, self.name, "accepted", true)
                print("[TEST Quest] Quest accepted for player", player_id)
                
            elseif event_value == "complete" then
                -- Complete the quest (must be accepted first)
                local accepted = ezquests.get_player_quest_flag(player_id, self.name, "accepted")
                if accepted then
                    ezquests.set_player_quest_flag(player_id, self.name, "completed", true)
                    print("[TEST Quest] Quest completed for player", player_id)
                else
                    print("[TEST Quest] Cannot complete - quest not accepted yet.")
                end
                
            elseif event_value == "reset" then
                -- Clear all flags (reset quest)
                ezquests.clear_player_quest_flags(player_id, self.name)
                print("[TEST Quest] Quest reset for player", player_id)
                
            else
                print("[TEST Quest] Unknown event:", event_value)
            end
        end)
    end,
    
    -- determine_state returns a string based on current flags
    determine_state = function(self, player_id)
        local completed = ezquests.get_player_quest_flag(player_id, self.name, "completed")
        if completed then
            return "completed"
        end
        
        local accepted = ezquests.get_player_quest_flag(player_id, self.name, "accepted")
        if accepted then
            return "accepted"
        end
        
        return "unaccepted"
    end
})

print("[TEST Quest] Loaded successfully.")