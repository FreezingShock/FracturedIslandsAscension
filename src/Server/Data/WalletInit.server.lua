-- WalletInit (Script, ServerScriptService): loads WalletService early so every player's `Coins` attribute is set as soon as their profile loads.
require(game:GetService("ServerScriptService"):WaitForChild("WalletService"))
