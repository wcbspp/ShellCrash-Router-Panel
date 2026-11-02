-- A single atomic replacement keeps the two most recent bounded records.
return function(M, evidence)
 local path=M.C..'/configs/oom-records.json'
 local free=tonumber(M.exec("df -k /data | awk 'END{print $4}'")) or 0
 assert(free>=640,'insufficient_persistent_space')
 local raw=M.read(path,65537);assert(#raw<=65536,'previous_records_too_large')
 local records={}
 if raw~='' then
  local ok,old=pcall(M.json.decode,raw)
  assert(ok and type(old)=='table' and type(old.records)=='table' and #old.records<=2,'previous_records_invalid')
  for _,record in ipairs(old.records)do assert(type(record)=='table' and type(record.time)=='string' and type(record.pid)=='string','previous_records_invalid')end
  records=old.records
 end
 records[#records+1]=evidence
 while #records>2 do table.remove(records,1)end
 local serialized=M.json.encode({version=1,records=records})
 assert(#serialized<=65536,'records_too_large')
 local ok,err=pcall(function()
  M.write(path..'.new',serialized)
  assert(os.rename(path..'.new',path),'records_rename_failed')
 end)
 if not ok then os.remove(path..'.new');error(err)end
 assert(M.run('sync'),'records_sync_failed')
 assert(M.read(path,65537)==serialized,'records_readback_failed')
 return true
end
