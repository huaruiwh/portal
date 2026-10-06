import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const directory=path.join(root,'graph');
const escape=value=>String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
let uid=21;
const next=()=>uid++;
const symbol=(name,id)=>`<Access Scope="GlobalVariable" UId="${id}"><Symbol>${name.split('.').map(part=>`<Component Name="${part}"/>`).join('')}</Symbol></Access>`;
function network(contacts,terminal,operand){
 const parts=[],wires=[];let previous=null;
 const connect=(from,to)=>wires.push(`<Wire UId="${next()}">${from===null?'<Powerrail/>':`<NameCon UId="${from}" Name="out"/>`}<NameCon UId="${to}" Name="in"/></Wire>`);
 for(const [name,negated] of contacts){const access=next(),part=next();parts.push(symbol(name,access),`<Part Name="Contact" UId="${part}">${negated?'<Negated Name="operand"/>':''}</Part>`);connect(previous,part);wires.push(`<Wire UId="${next()}"><IdentCon UId="${access}"/><NameCon UId="${part}" Name="operand"/></Wire>`);previous=part;}
 const coil=next();parts.push(`<Part Name="${terminal}" UId="${coil}"/>`);connect(previous,coil);
 if(operand){const access=next();parts.push(symbol(operand,access));wires.push(`<Wire UId="${next()}"><IdentCon UId="${access}"/><NameCon UId="${coil}" Name="operand"/></Wire>`);}
 return `<FlgNet><Parts>${parts.join('')}</Parts><Wires>${wires.join('')}</Wires></FlgNet>`;
}
const action=(qualifier,tag,delay)=>`<Action Qualifier="${qualifier}"><Token Text="${escape('"'+tag+'"')}"/>${delay?`<Token Text=","/><Token Text="${escape('"MotorSequence_Settings".'+delay)}"/>`:''}<Token Text="&#xA;"/></Action>`;
const run=(qualifier,tag)=>[qualifier,tag];
export const states=[
 {number:1,name:'Idle',title:'空闲：全部停止，等待新的启动上升沿',actions:[run('R','Motor1_Active'),run('R','Motor2_Active'),run('R','Motor3_Active'),run('R','Stop_Latched'),run('N','Graph_Idle')]},
 {number:2,name:'Start1',title:'1号运行：等待启动间隔，停止优先',actions:[run('S','Motor1_Active'),run('N','Graph_Start1'),['D','Start2_Done','StartInterval']]},
 {number:3,name:'Start12',title:'1、2号运行：等待启动间隔，停止可跳至只留1号',actions:[run('S','Motor2_Active'),run('N','Graph_Start12'),['D','Start3_Done','StartInterval']]},
 {number:4,name:'AllRunning',title:'三台电机全部运行，等待停止',actions:[run('S','Motor3_Active'),run('N','Graph_AllRunning')]},
 {number:5,name:'Stop12',title:'立即停3号，锁存停止序列，等待停止间隔',actions:[run('R','Motor3_Active'),run('S','Stop_Latched'),run('N','Graph_Stop12'),['D','Stop2_Done','StopInterval']]},
 {number:6,name:'Stop1',title:'立即停2号，保持1号至停止间隔结束',actions:[run('R','Motor2_Active'),run('R','Motor3_Active'),run('S','Stop_Latched'),run('N','Graph_Stop1'),['D','Stop1_Done','StopInterval']]},
];
const transitions=[
 [1,'Start',[['Start_Pulse'],['Stop_Command',true]]],
 [2,'StopDuring1',[['Stop_Command']]],
 [3,'Start2',[['Start2_Done'],['Stop_Command',true]]],
 [4,'StopDuring12',[['Stop_Command']]],
 [5,'Start3',[['Start3_Done'],['Stop_Command',true]]],
 [6,'BeginStop',[['Stop_Command']]],
 [7,'Stop2',[['Stop2_Done']]],
 [8,'Stop1',[['Stop1_Done']]],
];
const step=n=>`<StepRef Number="${n}"/>`,trans=n=>`<TransitionRef Number="${n}"/>`,branch=(n,direction,index)=>`<BranchRef Number="${n}" ${direction}="${index}"/>`;
const links=[];
const link=(from,to,type='Direct')=>links.push(`<Connection><NodeFrom>${from}</NodeFrom><NodeTo>${to}</NodeTo><LinkType>${type}</LinkType></Connection>`);
link(step(1),trans(1));link(trans(1),step(2));
link(step(2),branch(1,'In',0));link(branch(1,'Out',0),trans(2));link(trans(2),step(1),'Jump');link(branch(1,'Out',1),trans(3));link(trans(3),step(3));
link(step(3),branch(2,'In',0));link(branch(2,'Out',0),trans(4));link(trans(4),step(6),'Jump');link(branch(2,'Out',1),trans(5));link(trans(5),step(4));
link(step(4),trans(6));link(trans(6),step(5));link(step(5),trans(7));link(trans(7),step(6));link(step(6),trans(8));link(trans(8),step(1),'Jump');
const iface=fs.readFileSync(path.join(directory,'template/GRAPH_interface.xml'),'utf8');
const operation=(contacts,target)=>`<PermanentOperation ProgrammingLanguage="LAD">${network(contacts,'Coil',target)}</PermanentOperation>`;
const stepXml=states.map(s=>`<Step Number="${s.number}" Init="${s.number===1}" Name="${s.name}" MaximumStepTime="T#0ms" WarningTime="T#0ms"><Actions><Title><MultiLanguageText Lang="zh-CN">${escape(s.title)}</MultiLanguageText></Title>${s.actions.map(a=>action(...a)).join('')}<Action/></Actions><Supervisions><Supervision ProgrammingLanguage="LAD">${network([['Stop_Command'],['Stop_Command',true]],'SvCoil')}</Supervision></Supervisions><Interlocks><Interlock ProgrammingLanguage="LAD">${network([],'IlCoil')}</Interlock></Interlocks></Step>`).join('\n');
const alarms=`<AlarmsSettings><AlarmSupervisionCategories>${Array.from({length:8},(_,i)=>`<AlarmSupervisionCategory Id="${i+1}" DisplayClass="0"/>`).join('')}</AlarmSupervisionCategories><AlarmInterlockCategory Id="1"/><AlarmSubcategory1Interlock Id="0"/><AlarmSubcategory2Interlock Id="0"/><AlarmCategorySupervision Id="1"/><AlarmSubcategory1Supervision Id="0"/><AlarmSubcategory2Supervision Id="0"/><AlarmWarningCategory Id="2"/><AlarmSubcategory1Warning Id="0"/><AlarmSubcategory2Warning Id="0"/></AlarmsSettings>`;
const graph=`<?xml version="1.0" encoding="utf-8"?><Document><Engineering version="V20"/><SW.Blocks.FB ID="0"><AttributeList><AutoNumber>false</AutoNumber><GraphVersion>6.0</GraphVersion>${iface}<Name>MotorSequenceGRAPH</Name><Namespace/><Number>2</Number><ProgrammingLanguage>GRAPH</ProgrammingLanguage><SetENOAutomatically>false</SetENOAutomatically></AttributeList><ObjectList><SW.Blocks.CompileUnit ID="1" CompositionName="CompileUnits"><AttributeList><NetworkSource><Graph xmlns="http://www.siemens.com/automation/Openness/SW/NetworkSource/Graph/v5"><PreOperations>${operation([['Start_Command'],['Start_Previous',true]],'Start_Pulse')}</PreOperations><Sequence><Title><MultiLanguageText Lang="zh-CN">三电机顺序启停：DB2可设间隔</MultiLanguageText></Title><Comment><MultiLanguageText Lang="zh-CN">停止优先；停止阶段保持到全部停止；长按启动不自动重启。使用GRAPH原生D延时动作。</MultiLanguageText></Comment><Steps>${stepXml}</Steps><Transitions>${transitions.map(([n,name,contacts])=>`<Transition IsMissing="false" Name="T_${name}" Number="${n}" ProgrammingLanguage="LAD">${network(contacts,'TrCoil')}</Transition>`).join('\n')}</Transitions><Branches><Branch Number="1" Type="AltBegin" Cardinality="2"/><Branch Number="2" Type="AltBegin" Cardinality="2"/></Branches><Connections>${links.join('\n')}</Connections></Sequence><PostOperations>${[1,2,3].map(i=>operation([[`Motor${i}_Active`]],`Motor_${i}`)).join('')}${operation([['Start_Command']],'Start_Previous')}</PostOperations>${alarms}</Graph></NetworkSource><ProgrammingLanguage>GRAPH</ProgrammingLanguage></AttributeList></SW.Blocks.CompileUnit></ObjectList></SW.Blocks.FB></Document>`;
const main=fs.readFileSync(path.join(root,'xml/Main_OB1.xml'),'utf8').replaceAll('MotorSequenceLAD','MotorSequenceGRAPH').replaceAll('MotorSequence_DB','MotorSequence_GRAPH_DB');
// Explicit automatic mode; the GRAPH runtime initialization flag initializes the initial step.
const ob=main.replace('</CallInfo>','<Parameter Name="SW_AUTO" Section="Input" Type="Bool"/></CallInfo>').replace('</Parts>','<Access Scope="LiteralConstant" UId="40"><Constant><ConstantType>Bool</ConstantType><ConstantValue>true</ConstantValue></Constant></Access></Parts>').replace('</Wires>','<Wire UId="41"><IdentCon UId="40"/><NameCon UId="21" Name="SW_AUTO"/></Wire></Wires>');
fs.writeFileSync(path.join(directory,'xml/MotorSequenceGRAPH.xml'),graph);fs.writeFileSync(path.join(directory,'xml/Main_GRAPH.xml'),ob);
console.log(JSON.stringify({language:'GRAPH',steps:states.length,transitions:transitions.length,branches:2,connections:links.length,delayedActions:4,parameterDB:'MotorSequence_Settings'}));
