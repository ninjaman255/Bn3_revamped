local sha       = require('scripts/octo-ranking/sha256')

local seed_pass = "INPUT_YOUR_SEED_HERE"
local pass_seed = sha.sha256(seed_pass)

return pass_seed
