const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),html=fs.readFileSync(path.join(root,fs.existsSync(path.join(root,'ui/index.html'))?'ui/index.html':'payload/ui/index.html'),'utf8');
const source=html.match(/function autoMeasure\(\)[^\n]+/)[0];
let calls=[],pauses=0;const c=vm.createContext({nativeState:{pressure:'normal'},siteBusy:false,running:true,manageBusy:false,activeTab:'nodes',document:{hidden:false},el:()=>({children:[{dataset:{name:'A'}},{dataset:{name:'A'}},{dataset:{name:'B'}}]}),pauseMeasurements:()=>pauses++,queueMeasurements:n=>calls.push(Array.from(n))});vm.runInContext(source,c);
c.autoMeasure();assert.deepEqual(calls,[['A','B']]);assert.equal(pauses,1);
for(const pressure of ['warning','protect']){c.nativeState.pressure=pressure;c.autoMeasure();assert.equal(calls.length,1);assert.equal(pauses,1);}
c.nativeState.pressure='normal';c.autoMeasure();assert.equal(calls.length,2);
// The gate only schedules browser samples; it never changes kernel groups/mode.
assert(!source.includes('PUT')&&!source.includes('DELETE')&&!source.includes('setProxyMode'));
c.document.hidden=true;c.autoMeasure();assert.equal(calls.length,2);
console.log('browser auto-delay pauses under warning/protection, resumes normal, deduplicates nodes and leaves kernel selection untouched');
