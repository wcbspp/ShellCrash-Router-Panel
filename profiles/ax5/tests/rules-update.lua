local source=arg[1]or'/data/ShellCrash/ax5/rules-update.lua'
local A=dofile(source)
local old,new='223.5.5.0/24\n','223.5.5.0/24\n8.152.0.0/13\n'
local realrename=os.rename
for _,scenario in ipairs({'success','unchanged','put-fail','count-mismatch','rollback-fail'})do
 local files={['/fixture/configs/cn_ip.txt']=old};local calls=0;local loaded=1
 os.rename=function(a,b)files[b]=files[a];files[a]=nil;return true end
 local M={C='/fixture',read=function(p)return files[p]or''end,write=function(p,t)files[p]=t end,json={decode=function(d)return d end},request=function(path,method)
  if method=='PUT'then calls=calls+1;if scenario=='rollback-fail'or(scenario=='put-fail'and calls==1)then return'',503 end
   loaded=files['/fixture/configs/cn_ip.txt']==old and 1 or 2;return'',204
  end
  return {providers={['panel-cn-ip']={vehicleType='File',ruleCount=(scenario=='count-mismatch'and calls==1)and 999 or loaded}}},200
 end}
 local ok,result=pcall(A.apply,M,scenario=='unchanged'and old or new,2)
 if scenario=='success'then assert(ok and result and files['/fixture/configs/cn_ip.txt']==new and loaded==2)
 elseif scenario=='unchanged'then assert(ok and result==false and calls==0)
 else assert(not ok and files['/fixture/configs/cn_ip.txt']==old);if scenario=='rollback-fail'then assert(result:find('待确认',1,true))else assert(loaded==1 and result:find('已恢复',1,true))end end
 assert(files['/fixture/configs/cn_ip.txt.new']==nil)
end
os.rename=realrename
print('domestic fallback hot reload: success, no-op, load/readback failure rollback and unresolved rollback reporting passed')
