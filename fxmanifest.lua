fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'push_gates'
author 'XanderP'
description 'Push gates open by hand instead of them opening on their own. discord.gg/cMqazwj6c7'
version '2.1.0'

--[[ No framework and no hard dependencies. ox_target, qb-target and BS19 are
     checked at runtime and only used if theyre actually running, so this
     starts fine on a server with none of them. ]]

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

shared_script 'config.lua'

client_scripts {
    'client/main.lua',
    'client/menu.lua',
    'client/commands.lua',
}

server_script 'server/main.lua'
