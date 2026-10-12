local N=dofile(arg[1]or'/data/ShellCrash/ax5/node-identity.lua')
local old={{type='anytls',tag='台湾01',server='test.invalid',server_port=443,password='fixture'}}
local new={{type='anytls',tag='🇹🇼 台湾01',server='test.invalid',server_port=443,password='fixture'},{type='selector',tag='地区/台湾',outbounds={'🇹🇼 台湾01'},default='🇹🇼 台湾01'}}
N.preserve(old,new);assert(new[1].tag=='台湾01'and new[2].outbounds[1]=='台湾01'and new[2].default=='台湾01')
N.validate_targets({outbounds=new,route={rules={{outbound='台湾01'}}}})
assert(not pcall(N.validate_targets,{outbounds=new,route={rules={{outbound='removed'}}}}))
local changed={{type='anytls',tag='decorated',server='test.invalid',server_port=443,password='changed'}}
N.preserve(old,changed);assert(changed[1].tag=='decorated')
local ambiguous={old[1],{type='anytls',tag='other',server='test.invalid',server_port=443,password='fixture'}}
local duplicate={{type='anytls',tag='new',server='test.invalid',server_port=443,password='fixture'}}
N.preserve(ambiguous,duplicate);assert(duplicate[1].tag=='new')
print('conversion renaming preserves routing references; changed credentials and ambiguous matches are rejected')

local converted={{type='anytls',tag='🇹🇼 台湾01',server='test.invalid',server_port=443,password='fixture'},{type='selector',tag='分流/ChatGPT',outbounds={'🇹🇼 台湾01'},default='台湾01'}}
N.preserve(old,converted);N.validate_targets({outbounds=converted,route={rules={{outbound='分流/ChatGPT'}}}});assert(converted[2].outbounds[1]=='台湾01'and converted[2].default=='台湾01')
converted[2].default='missing';assert(not pcall(N.validate_targets,{outbounds=converted,route={rules={}}}));converted[2].default='台湾01';converted[2].outbounds={'missing'};assert(not pcall(N.validate_targets,{outbounds=converted,route={rules={}}}))
print('preset references validate after identity matching; real missing members/defaults are rejected')
