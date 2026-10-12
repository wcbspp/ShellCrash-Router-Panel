local A={}
local function require_ok(ok,msg)if not ok then error(msg or "database_operation_failed",0)end;return ok end
function A.update(M,service)
 local kind=M.read(M.C..'/cache/core.env'):match('KIND=([^%s]+)')
 require_ok(kind=='meta'or kind=='singbox','invalid_core')
 local ext=kind=='meta'and'mrs'or'srs'
 local path=M.C..'/ruleset/cn.'..ext
 local candidate=M.R..'/domain-candidate.'..ext
 local previous=M.R..'/domain-previous.'..ext
 local preview=M.R..'/domain-check.'..(kind=='meta'and'yaml'or'json')
 local changed,paused=false,false
 local wasrunning=M.pid()>0
 local function cleanup()
  for _,p in ipairs({candidate,previous,preview,M.R..'/domain-source'})do os.remove(p)end
 end
 local ok,result=pcall(function()
  require_ok(M.run(M.C..'/ax5/database-source.sh '..kind..' >> '..M.R..'/service.log 2>&1'),'database_download_failed')
  local size=#M.read(candidate,2000001)
  require_ok(size>1024 and size<2000000,'database_invalid')
  local hash=M.exec('openssl dgst -sha256 '..M.quote(candidate)):match('(%x+)%s*$')
  require_ok(hash and #hash==64,'database_invalid')
  local oldhash=M.exec('openssl dgst -sha256 '..M.quote(path)..' 2>/dev/null'):match('(%x+)%s*$')
  M.save(M.R..'/domain-check.json',{kind=kind,file='cn.'..ext,sha256=hash,checked=os.time()})
  if hash==oldhash then return 'database_unchanged'end
  local free=tonumber(M.exec('df -k '..M.C..' | awk "END {print \\$4}"'))or 0
  require_ok(free*1024>size+524288,'database_space_insufficient')
  require_ok(M.run('cp '..M.quote(path)..' '..M.quote(previous)),'database_backup_failed')
  local cfg=M.load(M.C..'/configs/config.json')
  if kind=='meta'then
   cfg=dofile(M.C..'/ax5/mihomo.lua').build(cfg);cfg['rule-providers'].cn.path=candidate
  else
   local found=false
   for _,r in ipairs(cfg.route.rule_set or{})do if r.tag=='cn'then r.path=candidate;found=true end end
   require_ok(found,'configuration_template_missing')
  end
  M.write(preview,M.encode(cfg):gsub('\\/','/'));cfg=nil;collectgarbage('collect')
  if wasrunning then service('stop');paused=true end
  local command
  if kind=='meta'then command=M.C..'/ax5/check-binary.sh meta '..M.R..'/CrashCore -t -d '..M.R..' -f '..preview
  else command='GOMEMLIMIT=12MiB GOGC=25 '..M.R..'/CrashCore check -D '..M.R..' -c '..preview end
  require_ok(M.run(command..' >> '..M.R..'/service.log 2>&1'),'database_check_failed')
  require_ok(M.run('cp '..M.quote(candidate)..' '..M.quote(path..'.new')),'database_save_failed')
  require_ok(os.rename(path..'.new',path));changed=true
  if wasrunning then service('start');paused=false end
  M.save(M.C..'/configs/domain-'..kind..'.json',{kind=kind,file='cn.'..ext,sha256=hash,updated=os.time(),source=M.read(M.R..'/domain-source'):gsub('%s+$','')})
  if not M.run(M.C..'/ax5/backup-config.sh >> '..M.R..'/service.log 2>&1')then return 'configuration_saved_backup_pending'end
  return 'database_updated'
 end)
 if not ok then
  if changed then
   pcall(service,'stop')
   require_ok(M.run('cp '..M.quote(previous)..' '..M.quote(path..'.new')),'database_rollback_failed')
   require_ok(os.rename(path..'.new',path))
  end
  if wasrunning and(paused or changed)then pcall(service,'start')end
 end
 cleanup()
 if not ok then error(result,0)end
 return result
end
return A
