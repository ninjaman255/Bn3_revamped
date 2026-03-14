local ezconfig = {}

-- Feature flags
ezconfig.EZFARMS_ENABLED = false
ezconfig.FARM_MAP = ""
ezconfig.EZCHRISTMAS_ENABLED = false

-- File paths
ezconfig.PLAYERS_PATH = './memory/players.json'
ezconfig.ITEMS_PATH = './memory/items.json'
ezconfig.AREA_PATH_FOLDER = './memory/area/'
ezconfig.PLAYER_PATH_FOLDER = './memory/player/'
ezconfig.BOARD_PATH_FOLDER = './memory/board/'
ezconfig.ENCOUNTERS_PATH = './encounters/'
ezconfig.NPC_ASSET_FOLDER = '/server/assets/ezlibs-assets/eznpcs/'
ezconfig.NPC_EVENTS_SCRIPT_PATH = './scripts/events/'

-- Admin password seed (plaintext – will be hashed by ezusers)
ezconfig.ADMIN_SEED = "INPUT_YOUR_SEED_HERE" -- ← change this to your desired admin password

return ezconfig
