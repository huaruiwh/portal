import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const c=(addr,nc=false)=>({kind:'contact',addr,nc});
const coil=(addr,mode='Coil')=>({kind:'coil',addr,mode});
const timer=(name)=>({kind:'timer',name,parameter:name.startsWith('Start')?'StartInterval':'StopInterval'});
const any={kind:'or',branches:[[c('Active1')],[c('Active2')],[c('Active3')]]};
export const networks=[
 ['启动上升沿，仅接受新的按钮动作',[c('Start'),c('PreviousStart',true),coil('StartPulse')]],
 ['停止事件：正在运行且尚未进入停止序列',[c('Stop'),c('Stopping',true),any,coil('StopEvent')]],
 ['停机前快照：3号已启动',[c('StopEvent'),c('Active3'),coil('Had3')]],
 ['停机前快照：2号已启动',[c('StopEvent'),c('Active2'),coil('Had2')]],
 ['锁存停止请求，松开停止按钮仍完成序列',[c('StopEvent'),coil('Stopping','SCoil')]],
 ['立即停当前最后启动的3号电机',[c('StopEvent'),c('Had3'),coil('Active3','RCoil')]],
 ['若3号未启动，立即停2号电机',[c('StopEvent'),c('Had3',true),c('Had2'),coil('Active2','RCoil')]],
 ['若仅1号运行，立即停1号电机',[c('StopEvent'),c('Had3',true),c('Had2',true),coil('Active1','RCoil')]],
 ['空闲时启动1号；停止优先，停止期间禁止重启',[c('StartPulse'),c('Stop',true),c('Stopping',true),c('Active1',true),c('Active2',true),c('Active3',true),coil('Active1','SCoil')]],
 ['1号启动后按启动间隔计时',[c('Active1'),c('Stopping',true),c('Stop',true),timer('Start2'),coil('Start2Done')]],
 ['启动间隔到，锁存2号运行状态',[c('Start2Done'),c('Stopping',true),coil('Active2','SCoil')]],
 ['2号启动后再按启动间隔计时',[c('Active2'),c('Stopping',true),c('Stop',true),timer('Start3'),coil('Start3Done')]],
 ['启动间隔到，锁存3号运行状态',[c('Start3Done'),c('Stopping',true),coil('Active3','SCoil')]],
 ['3号停止后按停止间隔计时，保持2号运行',[c('Stopping'),c('Active2'),timer('Stop2'),coil('Stop2Done')]],
 ['停止间隔到，停止2号',[c('Stop2Done'),coil('Active2','RCoil')]],
 ['2号停止后按停止间隔计时，保持1号运行',[c('Stopping'),c('Active1'),c('Active2',true),timer('Stop1'),coil('Stop1Done')]],
 ['停止间隔到，停止1号',[c('Stop1Done'),coil('Active1','RCoil')]],
 ['全部停止后释放停止请求',[c('Active1',true),c('Active2',true),c('Active3',true),coil('Stopping','RCoil')]],
 ['1号物理输出',[c('Active1'),coil('Motor1')]],
 ['2号物理输出',[c('Active2'),coil('Motor2')]],
 ['3号物理输出',[c('Active3'),coil('Motor3')]],
 ['记录启动按钮，用于下一扫描周期的上升沿',[c('Start'),coil('PreviousStart')]],
];
const esc=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
let uid=100,id=100;
function unit(title,flow){
 const parts=[],wires=[]; const next=()=>uid++;
 const conn=(a,p,b,q)=>wires.push(`<Wire UId="${next()}">${a===null?'<Powerrail/>':`<NameCon UId="${a}" Name="${p}"/>`}<NameCon UId="${b}" Name="${q}"/></Wire>`);
 const operand=(a,b)=>wires.push(`<Wire UId="${next()}"><IdentCon UId="${a}"/><NameCon UId="${b}" Name="operand"/></Wire>`);
 function address(addr){const n=next();parts.push(`<Access Scope="LocalVariable" UId="${n}"><Symbol><Component Name="${addr}"/></Symbol></Access>`);return n;}
 function emit(items,prev=null,pin='out'){
  for(const el of items){
   if(el.kind==='or'){const o=next();parts.push(`<Part Name="O" UId="${o}"><TemplateValue Name="Card" Type="Cardinality">${el.branches.length}</TemplateValue></Part>`);let b=1;for(const branch of el.branches){const end=emit(branch,prev,pin);conn(end.uid,end.pin,o,'in'+b++);}prev=o;pin='out';}
   else if(el.kind==='contact'||el.kind==='coil'){const a=address(el.addr),p=next();parts.push(`<Part Name="${el.kind==='contact'?'Contact':el.mode}" UId="${p}">${el.nc?'<Negated Name="operand"/>':''}</Part>`);conn(prev,pin,p,'in');operand(a,p);prev=p;pin='out';}
   else {const p=next(),instance=next(),pt=next(),open=next();parts.push(`<Part Name="TON" Version="1.0" UId="${p}"><Instance Scope="LocalVariable" UId="${instance}"><Component Name="${el.name}"/></Instance><TemplateValue Name="time_type" Type="Type">Time</TemplateValue></Part>`);parts.push(`<Access Scope="LocalVariable" UId="${pt}"><Symbol><Component Name="${el.parameter}"/></Symbol></Access>`);conn(prev,pin,p,'IN');wires.push(`<Wire UId="${next()}"><IdentCon UId="${pt}"/><NameCon UId="${p}" Name="PT"/></Wire>`);wires.push(`<Wire UId="${next()}"><NameCon UId="${p}" Name="ET"/><OpenCon UId="${open}"/></Wire>`);prev=p;pin='Q';}
  }return {uid:prev,pin};
 }
 emit(flow);
 const merged = new Map();
 for (const wire of wires) {
   const match = wire.match(/^<Wire UId="\d+">(<Powerrail\/>|<NameCon UId="\d+" Name="[^"]+"\/>)([\s\S]*)<\/Wire>$/);
   if (!match) { merged.set(wire, wire); continue; }
   const key=match[1];
   if (merged.has(key)) merged.set(key,merged.get(key).replace('</Wire>',match[2]+'</Wire>'));
   else merged.set(key,wire);
 }
 wires.splice(0,wires.length,...merged.values());
 return `<SW.Blocks.CompileUnit ID="${id++}" CompositionName="CompileUnits"><AttributeList><NetworkSource><FlgNet xmlns="http://www.siemens.com/automation/Openness/SW/NetworkSource/FlgNet/v5"><Parts>${parts.join('')}</Parts><Wires>${wires.join('')}</Wires></FlgNet></NetworkSource><ProgrammingLanguage>LAD</ProgrammingLanguage></AttributeList><ObjectList><MultilingualText ID="${id++}" CompositionName="Title"><ObjectList><MultilingualTextItem ID="${id++}" CompositionName="Items"><AttributeList><Culture>zh-CN</Culture><Text>${esc(title)}</Text></AttributeList></MultilingualTextItem></ObjectList></MultilingualText></ObjectList></SW.Blocks.CompileUnit>`;
}
if(process.argv[2]!=='--test-only') {
 let scaffold=fs.readFileSync(path.join(root,'reusable/verify/Scaffold_export.xml'),'utf8');
 const iface=scaffold.match(/<Interface>[\s\S]*?<\/Interface>/)[0];
 const fb=`<?xml version="1.0" encoding="utf-8"?><Document><Engineering version="V20"/><SW.Blocks.FB ID="0"><AttributeList><AutoNumber>true</AutoNumber><MemoryLayout>Optimized</MemoryLayout>${iface}<Name>MotorSequenceLAD</Name><Namespace/><Number>1</Number><ProgrammingLanguage>LAD</ProgrammingLanguage></AttributeList><ObjectList>${networks.map(([title,flow])=>unit(title,flow)).join('\n')}</ObjectList></SW.Blocks.FB></Document>`;
 const main=`<?xml version="1.0" encoding="utf-8"?><Document><Engineering version="V20"/><SW.Blocks.OB ID="0"><AttributeList><AutoNumber>false</AutoNumber><Interface><Sections xmlns="http://www.siemens.com/automation/Openness/SW/Interface/v5"><Section Name="Temp"/><Section Name="Constant"/></Sections></Interface><Name>Main</Name><Namespace/><SecondaryType>ProgramCycle</SecondaryType><Number>1</Number><ProgrammingLanguage>LAD</ProgrammingLanguage></AttributeList><ObjectList><SW.Blocks.CompileUnit ID="1" CompositionName="CompileUnits"><AttributeList><NetworkSource><FlgNet xmlns="http://www.siemens.com/automation/Openness/SW/NetworkSource/FlgNet/v5"><Parts><Call UId="21"><CallInfo Name="MotorSequenceLAD" BlockType="FB"><Instance Scope="GlobalVariable" UId="22"><Component Name="MotorSequence_DB"/></Instance></CallInfo></Call></Parts><Wires><Wire UId="23"><Powerrail/><NameCon UId="21" Name="en"/></Wire><Wire UId="24"><NameCon UId="21" Name="eno"/><OpenCon UId="25"/></Wire></Wires></FlgNet></NetworkSource><ProgrammingLanguage>LAD</ProgrammingLanguage></AttributeList></SW.Blocks.CompileUnit></ObjectList></SW.Blocks.OB></Document>`;
 fs.writeFileSync(path.join(root,'reusable/xml/MotorSequenceLAD.xml'),fb);console.log(JSON.stringify({networks:networks.length,timers:4}));
}
