import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
let uid=20,id=10;
const access=(name)=>{const u=uid++;return {u,xml:`<Access Scope="GlobalVariable" UId="${u}"><Symbol>${name.split('.').map(n=>`<Component Name="${n}"/>`).join('')}</Symbol></Access>`}};
function call(instance,scope,args){const c=uid++,inst=uid++;const parts=[],wires=[];const params=[];
 for(const [name,section,type,value] of args){const a=access(value);parts.push(a.xml);params.push(`<Parameter Name="${name}" Section="${section}" Type="${type}"/>`);wires.push(`<Wire UId="${uid++}"><IdentCon UId="${a.u}"/><NameCon UId="${c}" Name="${name}"/></Wire>`);}
 parts.push(`<Call UId="${c}"><CallInfo Name="${args.length?'MotorSequenceLAD':'MotorGroups'}" BlockType="FB"><Instance Scope="${scope}" UId="${inst}"><Component Name="${instance}"/></Instance>${params.join('')}</CallInfo></Call>`);
 wires.push(`<Wire UId="${uid++}"><Powerrail/><NameCon UId="${c}" Name="en"/></Wire>`,`<Wire UId="${uid++}"><NameCon UId="${c}" Name="eno"/><OpenCon UId="${uid++}"/></Wire>`);
 return `<SW.Blocks.CompileUnit ID="${id++}" CompositionName="CompileUnits"><AttributeList><NetworkSource><FlgNet xmlns="http://www.siemens.com/automation/Openness/SW/NetworkSource/FlgNet/v5"><Parts>${parts.join('')}</Parts><Wires>${wires.join('')}</Wires></FlgNet></NetworkSource><ProgrammingLanguage>LAD</ProgrammingLanguage></AttributeList></SW.Blocks.CompileUnit>`;
}
const args=g=>[['Start','Input','Bool',g===1?'Start_Command':'Group2_Start_Command'],['Stop','Input','Bool',g===1?'Stop_Command':'Group2_Stop_Command'],['StartInterval','Input','Time',g===1?'MotorSequence_Settings.StartInterval':'MotorSequence_Settings.Group2StartInterval'],['StopInterval','Input','Time',g===1?'MotorSequence_Settings.StopInterval':'MotorSequence_Settings.Group2StopInterval'],...['Motor1','Motor2','Motor3'].map((n,i)=>[n,'Output','Bool',g===1?`Motor_${i+1}`:`Group2_Motor_${i+1}`]),['Stopping','Output','Bool',g===1?'Stop_Latched':'Group2_Stopping']];
const iface=fs.readFileSync(path.join(root,'reusable/verify/GroupsScaffold_export.xml'),'utf8').match(/<Interface>[\s\S]*?<\/Interface>/)[0];
const groups=`<?xml version="1.0" encoding="utf-8"?><Document><Engineering version="V20"/><SW.Blocks.FB ID="0"><AttributeList><AutoNumber>false</AutoNumber><MemoryLayout>Optimized</MemoryLayout>${iface}<Name>MotorGroups</Name><Namespace/><Number>3</Number><ProgrammingLanguage>LAD</ProgrammingLanguage></AttributeList><ObjectList>${call('Group1','LocalVariable',args(1))}${call('Group2','LocalVariable',args(2))}</ObjectList></SW.Blocks.FB></Document>`;
const main=`<?xml version="1.0" encoding="utf-8"?><Document><Engineering version="V20"/><SW.Blocks.OB ID="0"><AttributeList><AutoNumber>false</AutoNumber><Interface><Sections xmlns="http://www.siemens.com/automation/Openness/SW/Interface/v5"><Section Name="Temp"/><Section Name="Constant"/></Sections></Interface><Name>Main</Name><Namespace/><SecondaryType>ProgramCycle</SecondaryType><Number>1</Number><ProgrammingLanguage>LAD</ProgrammingLanguage></AttributeList><ObjectList>${call('MotorGroups_DB','GlobalVariable',[])}</ObjectList></SW.Blocks.OB></Document>`;
fs.writeFileSync(path.join(root,'reusable/xml/MotorGroups.xml'),groups);fs.writeFileSync(path.join(root,'reusable/xml/Main_OB1.xml'),main);
console.log('Two local multi-instances, one global instance DB.');
