import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const c=(addr,nc=false)=>({kind:'contact',addr,nc});
const coil=(addr,mode='Coil')=>({kind:'coil',addr,mode});
const timer=(name)=>({kind:'timer',name,parameter:name.startsWith('Start')?'StartInterval':'StopInterval'});
const any={kind:'or',branches:[[c('M2.0')],[c('M2.1')],[c('M2.2')]]};
export const networks=[
 ['启动上升沿，仅接受新的按钮动作',[c('M0.0'),c('M4.0',true),coil('M4.1')]],
 ['停止事件：正在运行且尚未进入停止序列',[c('M0.1'),c('M3.0',true),any,coil('M4.2')]],
 ['停机前快照：3号已启动',[c('M4.2'),c('M2.2'),coil('M4.3')]],
 ['停机前快照：2号已启动',[c('M4.2'),c('M2.1'),coil('M4.4')]],
 ['锁存停止请求，松开停止按钮仍完成序列',[c('M4.2'),coil('M3.0','SCoil')]],
 ['立即停当前最后启动的3号电机',[c('M4.2'),c('M4.3'),coil('M2.2','RCoil')]],
 ['若3号未启动，立即停2号电机',[c('M4.2'),c('M4.3',true),c('M4.4'),coil('M2.1','RCoil')]],
 ['若仅1号运行，立即停1号电机',[c('M4.2'),c('M4.3',true),c('M4.4',true),coil('M2.0','RCoil')]],
 ['空闲时启动1号；停止优先，停止期间禁止重启',[c('M4.1'),c('M0.1',true),c('M3.0',true),c('M2.0',true),c('M2.1',true),c('M2.2',true),coil('M2.0','SCoil')]],
 ['1号启动后按启动间隔计时',[c('M2.0'),c('M3.0',true),c('M0.1',true),timer('Start2'),coil('M5.0')]],
 ['启动间隔到，锁存2号运行状态',[c('M5.0'),c('M3.0',true),coil('M2.1','SCoil')]],
 ['2号启动后再按启动间隔计时',[c('M2.1'),c('M3.0',true),c('M0.1',true),timer('Start3'),coil('M5.1')]],
 ['启动间隔到，锁存3号运行状态',[c('M5.1'),c('M3.0',true),coil('M2.2','SCoil')]],
 ['3号停止后按停止间隔计时，保持2号运行',[c('M3.0'),c('M2.1'),timer('Stop2'),coil('M5.2')]],
 ['停止间隔到，停止2号',[c('M5.2'),coil('M2.1','RCoil')]],
 ['2号停止后按停止间隔计时，保持1号运行',[c('M3.0'),c('M2.0'),c('M2.1',true),timer('Stop1'),coil('M5.3')]],
 ['停止间隔到，停止1号',[c('M5.3'),coil('M2.0','RCoil')]],
 ['全部停止后释放停止请求',[c('M2.0',true),c('M2.1',true),c('M2.2',true),coil('M3.0','RCoil')]],
 ['1号物理输出',[c('M2.0'),coil('Q0.0')]],
 ['2号物理输出',[c('M2.1'),coil('Q0.1')]],
 ['3号物理输出',[c('M2.2'),coil('Q0.2')]],
 ['记录启动按钮，用于下一扫描周期的上升沿',[c('M0.0'),coil('M4.0')]],
];
const esc=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
let uid=100,id=100;
function unit(title,flow){
 const parts=[],wires=[]; const next=()=>uid++;
 const conn=(a,p,b,q)=>wires.push(`<Wire UId="${next()}">${a===null?'<Powerrail/>':`<NameCon UId="${a}" Name="${p}"/>`}<NameCon UId="${b}" Name="${q}"/></Wire>`);
 const operand=(a,b)=>wires.push(`<Wire UId="${next()}"><IdentCon UId="${a}"/><NameCon UId="${b}" Name="operand"/></Wire>`);
 function address(addr){const n=next(),[byte,bit]=addr.slice(1).split('.').map(Number);parts.push(`<Access Scope="Address" UId="${n}"><Address Area="${addr[0]==='M'?'Memory':'Output'}" Type="Bool" BitOffset="${byte*8+bit}"/></Access>`);return n;}
 function emit(items,prev=null,pin='out'){
  for(const el of items){
   if(el.kind==='or'){const o=next();parts.push(`<Part Name="O" UId="${o}"><TemplateValue Name="Card" Type="Cardinality">${el.branches.length}</TemplateValue></Part>`);let b=1;for(const branch of el.branches){const end=emit(branch,prev,pin);conn(end.uid,end.pin,o,'in'+b++);}prev=o;pin='out';}
   else if(el.kind==='contact'||el.kind==='coil'){const a=address(el.addr),p=next();parts.push(`<Part Name="${el.kind==='contact'?'Contact':el.mode}" UId="${p}">${el.nc?'<Negated Name="operand"/>':''}</Part>`);conn(prev,pin,p,'in');operand(a,p);prev=p;pin='out';}
   else {const p=next(),instance=next(),pt=next(),open=next();parts.push(`<Part Name="TON" Version="1.0" UId="${p}"><Instance Scope="LocalVariable" UId="${instance}"><Component Name="${el.name}"/></Instance><TemplateValue Name="time_type" Type="Type">Time</TemplateValue></Part>`);parts.push(`<Access Scope="GlobalVariable" UId="${pt}"><Symbol><Component Name="MotorSequence_Settings"/><Component Name="${el.parameter}"/></Symbol></Access>`);conn(prev,pin,p,'IN');wires.push(`<Wire UId="${next()}"><IdentCon UId="${pt}"/><NameCon UId="${p}" Name="PT"/></Wire>`);wires.push(`<Wire UId="${next()}"><NameCon UId="${p}" Name="ET"/><OpenCon UId="${open}"/></Wire>`);prev=p;pin='Q';}
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
 let scaffold=fs.readFileSync(path.join(root,'verify/TimerScaffold_export.xml'),'utf8');
 const iface=scaffold.match(/<Interface>[\s\S]*?<\/Interface>/)[0];
 const fb=`<?xml version="1.0" encoding="utf-8"?><Document><Engineering version="V20"/><SW.Blocks.FB ID="0"><AttributeList><AutoNumber>true</AutoNumber><MemoryLayout>Optimized</MemoryLayout>${iface}<Name>MotorSequenceLAD</Name><Namespace/><Number>1</Number><ProgrammingLanguage>LAD</ProgrammingLanguage></AttributeList><ObjectList>${networks.map(([title,flow])=>unit(title,flow)).join('\n')}</ObjectList></SW.Blocks.FB></Document>`;
 const main=`<?xml version="1.0" encoding="utf-8"?><Document><Engineering version="V20"/><SW.Blocks.OB ID="0"><AttributeList><AutoNumber>false</AutoNumber><Interface><Sections xmlns="http://www.siemens.com/automation/Openness/SW/Interface/v5"><Section Name="Temp"/><Section Name="Constant"/></Sections></Interface><Name>Main</Name><Namespace/><SecondaryType>ProgramCycle</SecondaryType><Number>1</Number><ProgrammingLanguage>LAD</ProgrammingLanguage></AttributeList><ObjectList><SW.Blocks.CompileUnit ID="1" CompositionName="CompileUnits"><AttributeList><NetworkSource><FlgNet xmlns="http://www.siemens.com/automation/Openness/SW/NetworkSource/FlgNet/v5"><Parts><Call UId="21"><CallInfo Name="MotorSequenceLAD" BlockType="FB"><Instance Scope="GlobalVariable" UId="22"><Component Name="MotorSequence_DB"/></Instance></CallInfo></Call></Parts><Wires><Wire UId="23"><Powerrail/><NameCon UId="21" Name="en"/></Wire><Wire UId="24"><NameCon UId="21" Name="eno"/><OpenCon UId="25"/></Wire></Wires></FlgNet></NetworkSource><ProgrammingLanguage>LAD</ProgrammingLanguage></AttributeList></SW.Blocks.CompileUnit></ObjectList></SW.Blocks.OB></Document>`;
 fs.writeFileSync(path.join(root,'xml/MotorSequenceLAD.xml'),fb);fs.writeFileSync(path.join(root,'xml/Main_OB1.xml'),main);console.log(JSON.stringify({networks:networks.length,timers:4}));
}
