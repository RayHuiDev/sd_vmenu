fx_version 'cerulean'
game 'gta5'

name 'sd_vmenu'
description 'Auto-discovering local Stream Deck bridge for vMenu/FiveM focused actions'
author 'Hui + ChatGPT'
version '0.13.0'

ui_page 'html/index.html'
files { 'html/index.html' }

shared_script 'config.lua'
client_script 'client.lua'
server_script 'server.lua'
