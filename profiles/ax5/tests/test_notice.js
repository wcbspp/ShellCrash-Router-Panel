const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const root=path.resolve(__dirname,'..'),file=fs.existsSync(path.join(root,'ui/index.html'))?'ui/index.html':'payload/ui/index.html';
const html=fs.readFileSync(path.join(root,file),'utf8'),source=html.match(/let noticeTimer=null;[\s\S]*?el\('msg-close'\)\.onclick=\(\)=>note\(''\);/)[0];
const elements={msg:{hidden:true,dataset:{},classList:{toggle(){}}},'msg-text':{textContent:''},'msg-close':{}};let clock=0,id=0;const timers=new Map();
const ctx=vm.createContext({el:k=>elements[k],setTimeout:(fn,ms)=>{timers.set(++id,{fn,at:clock+ms});return id},clearTimeout:n=>timers.delete(n)});vm.runInContext(source,ctx);
function tick(ms){clock+=ms;for(const [n,t]of [...timers])if(t.at<=clock){timers.delete(n);t.fn()}}
ctx.note('成功');tick(4999);assert.equal(elements.msg.hidden,false);tick(1);assert.equal(elements.msg.hidden,true);
ctx.note('失败',true);tick(5000);assert.equal(elements.msg.hidden,false);tick(10000);assert.equal(elements.msg.hidden,true);
ctx.note('旧提示');tick(4000);ctx.note('新提示');tick(1000);assert.equal(elements.msg.hidden,false);assert.equal(elements['msg-text'].textContent,'新提示');tick(4000);assert.equal(elements.msg.hidden,true);
ctx.note('正在保存',false,{pending:true});tick(60000);assert.equal(elements.msg.hidden,false);assert.equal(timers.size,0);ctx.note('完成');tick(5000);assert.equal(elements.msg.hidden,true);
ctx.note('手动关闭',true);elements['msg-close'].onclick();assert.equal(elements.msg.hidden,true);assert.equal(timers.size,0);
ctx.note('旧成功');ctx.note('处理中',false,{pending:true});tick(5000);assert.equal(elements.msg.hidden,false);ctx.note('');assert.equal(elements.msg.hidden,true);
console.log('notice: success/error expiry, replacement race, persistent progress, manual close passed');
