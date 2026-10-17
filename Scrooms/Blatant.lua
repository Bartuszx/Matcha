task.spawn(function()
    while true do
        game.ReplicatedStorage.Network.Remotes.Minigame:FireServer("startSession", 1)
        game.ReplicatedStorage.Network.Remotes.Minigame:FireServer("claimSession", true, false)
        task.wait(.5)
    end
end)