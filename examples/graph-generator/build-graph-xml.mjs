// Builds a TIA Portal V20 S7-GRAPH block XML for the new demo project.
//
// Ground truth (learned by exporting a real GRAPH FB from a TIA V20 sample project
// on this machine, see refs/exported/*.xml):
//   * every LAD network inside <Graph> ends in a GRAPH coil:
//       Transition  -> <Part Name="TrCoil"/>
//       Interlock   -> <Part Name="IlCoil"/>
//       Supervision -> <Part Name="SvCoil"/>
//     (a plain <Part Name="Coil"/> belongs to Pre/Post operations instead)
//   * those coils only have a power-flow pin ("in") - no operand pin
//   * <Graph> carries the Graph/v5 namespace and the inner <FlgNet> inherits it
//   * the FB interface must contain the GRAPH base section (Datatype="GRAPH_BASE")
//     plus the system parameters TIA generates for GRAPH blocks
//   * no <MemoryLayout> element is written for GRAPH FBs
//   * branch nodes (选择分支 / 并行分支) are declared in <Branches> as
//       <Branch Number="n" Type="AltBegin|AltEnd|SimBegin|SimEnd" Cardinality="k" />
//     and wired through <BranchRef Number="n" In="i" /> / <BranchRef Number="n" Out="i" />.
//     The allowed neighbours are NOT symmetric. Verified against TIA V20 import errors:
//       "A connection between Step3 and Branch 2 cannot be created"   (步 -> AltEnd  不行)
//       "A connection between Trans2 and Branch 1 cannot be created"  (转换 -> AltBegin 不行)
//       "A connection between Trans7 and Branch 4 cannot be created"  (转换 -> SimEnd 不行)
//     Working layout - whichever element the fan-out node splits is also the element that
//     merges back into the matching fan-in node:
//       选择分支 AltBegin : 步 --直接--> AltBegin --Out i--> 转换 --> 步
//       选择分支 AltEnd   : 步 --> 转换 --> AltEnd In i --Out 0--> 步
//       并行分支 SimBegin : 步 --> 转换 --> SimBegin --Out i--> 步
//       并行分支 SimEnd   : 步 --直接--> SimEnd In i --Out 0--> 转换 --> 步
//     i.e. an alternative branch carries its transitions *inside* (one condition per branch
//     right after the fan-out), a simultaneous branch carries them *outside* (one shared
//     enable transition before the fan-out, one shared transition after the fan-in). Each
//     simultaneous branch therefore ends with a step; its branch-end condition sits on the
//     transition immediately before that step. (SimBegin matches refs/exported/GRAPH事件.xml)
//
// The interface is reused verbatim from the exported reference block (read-only),
// only block name/number and the sequence itself are generated here.
//
// Usage: node build-graph-xml.mjs [outputXmlPath] [referenceXmlPath]
import { writeFileSync, readFileSync, mkdirSync } from 'fs';
import { dirname, resolve } from 'path';
import { fileURLToPath } from 'url';

const here = dirname(fileURLToPath(import.meta.url));
const outPath = resolve(process.argv[2] || resolve(here, '..', 'xml', 'Graph_Sequencer.xml'));
const refPath = resolve(process.argv[3] || resolve(here, '..', 'refs', 'exported', 'GRAPH事件.xml'));

const BLOCK_NAME = 'Graph_Sequencer';
const BLOCK_NUMBER = 1;
const GRAPH_VERSION = '6.0';

// ── interface: reuse the GRAPH base/system interface from the reference export ──
const refXml = readFileSync(refPath, 'utf8');
const ifaceMatch = refXml.match(/<Interface>[\s\S]*?<\/Interface>/);
if (!ifaceMatch) throw new Error(`No <Interface> found in reference XML: ${refPath}`);
const interfaceXml = ifaceMatch[0];

// ── helpers ────────────────────────────────────────────────────────────────────
let uid = 21;
const nextUid = () => String(uid++);
const mlt = (t) => `<MultiLanguageText Lang="zh-CN">${t}</MultiLanguageText>`;

const globalAccess = (tag, id) =>
  `<Access Scope="GlobalVariable" UId="${id}"><Symbol><Component Name="${tag}" /></Symbol></Access>`;

const contact = (tag, { negated, id, partId }) =>
  [globalAccess(tag, id), `<Part Name="Contact" UId="${partId}">${negated ? '<Negated Name="operand" />' : ''}</Part>`];

/**
 * A GRAPH network: optional series contacts followed by a GRAPH terminal coil.
 * coilPart is one of TrCoil / IlCoil / SvCoil.
 */
function graphNetwork(contacts, coilPart) {
  const parts = [], wires = [];
  let prev = null;
  for (const c of contacts) {
    const id = nextUid(), partId = nextUid();
    parts.push(...contact(c.tag, { negated: c.negated, id, partId }));
    wires.push(prev
      ? `<Wire UId="${nextUid()}"><NameCon UId="${prev}" Name="out" /><NameCon UId="${partId}" Name="in" /></Wire>`
      : `<Wire UId="${nextUid()}"><Powerrail /><NameCon UId="${partId}" Name="in" /></Wire>`);
    wires.push(`<Wire UId="${nextUid()}"><IdentCon UId="${id}" /><NameCon UId="${partId}" Name="operand" /></Wire>`);
    prev = partId;
  }
  const coilId = nextUid();
  parts.push(`<Part Name="${coilPart}" UId="${coilId}" />`);
  wires.push(prev
    ? `<Wire UId="${nextUid()}"><NameCon UId="${prev}" Name="out" /><NameCon UId="${coilId}" Name="in" /></Wire>`
    : `<Wire UId="${nextUid()}"><Powerrail /><NameCon UId="${coilId}" Name="in" /></Wire>`);
  return `<FlgNet>
                  <Parts>
                    ${parts.join('\n                    ')}
                  </Parts>
                  <Wires>
                    ${wires.join('\n                    ')}
                  </Wires>
                </FlgNet>`;
}

// Action tables consist of one <Action> per line, each closed by a newline token, and the
// table itself is terminated by an empty <Action /> (format verified against real exports).
const actionXml = (a) =>
  `          <Action Qualifier="${a.qualifier}">` +
  `<Token Text="&quot;${a.tag}&quot;" /><Token Text="&#xA;" /></Action>`;

function stepXml(s) {
  return `      <Step Number="${s.number}" Init="${s.init ? 'true' : 'false'}" Name="${s.name}" MaximumStepTime="T#10S" WarningTime="T#7S">
        <Actions>
          <Title>${mlt(s.title)}</Title>
${s.actions.map(actionXml).join('\n')}
          <Action />
        </Actions>
        <Supervisions>
          <Supervision ProgrammingLanguage="LAD">
                ${graphNetwork(s.supervision, 'SvCoil')}
          </Supervision>
        </Supervisions>
        <Interlocks>
          <Interlock ProgrammingLanguage="LAD">
                ${graphNetwork(s.interlock, 'IlCoil')}
          </Interlock>
        </Interlocks>
      </Step>`;
}

function transitionXml(t) {
  const comment = t.comment ? `\n        <Comment>${mlt(t.comment)}</Comment>` : '';
  return `      <Transition IsMissing="false" Name="${t.name}" Number="${t.number}" ProgrammingLanguage="LAD">${comment}
        ${graphNetwork(t.contacts, 'TrCoil')}
      </Transition>`;
}

const connection = (from, to, linkType) => `      <Connection>
        <NodeFrom><${from} /></NodeFrom>
        <NodeTo><${to} /></NodeTo>
        <LinkType>${linkType}</LinkType>
      </Connection>`;

// sequence node references used inside <Connections>
const stepRef   = (n)    => `StepRef Number="${n}"`;
const transRef  = (n)    => `TransitionRef Number="${n}"`;
const branchIn  = (n, i) => `BranchRef Number="${n}" In="${i}"`;
const branchOut = (n, i) => `BranchRef Number="${n}" Out="${i}"`;

// ── the example sequence ───────────────────────────────────────────────────────
const steps = [
  { number: 1, name: 'Step1', init: true, title: '初始步：等待启动',
    actions: [
      { qualifier: 'R', tag: 'Run_Lamp' }, { qualifier: 'R', tag: 'Motor_1' },
      { qualifier: 'R', tag: 'Motor_2' }, { qualifier: 'R', tag: 'Motor_3' },
      { qualifier: 'R', tag: 'Valve_1' }, { qualifier: 'R', tag: 'Fan_1' },
      { qualifier: 'R', tag: 'Pump_1' },
    ],
    interlock: [{ tag: 'Interlock_Trip', negated: true }],
    supervision: [{ tag: 'Supervision_Trip' }] },
  { number: 2, name: 'Step2', init: false, title: '送料：电机 1 运行',
    actions: [{ qualifier: 'N', tag: 'Motor_1' }, { qualifier: 'S', tag: 'Run_Lamp' }],
    interlock: [{ tag: 'Interlock_Trip', negated: true }],
    supervision: [{ tag: 'Supervision_Trip' }] },
  { number: 3, name: 'Step3', init: false, title: '选择分支 A：正常加工（电机 2 运行）',
    actions: [{ qualifier: 'N', tag: 'Motor_2' }],
    interlock: [{ tag: 'Interlock_Trip', negated: true }],
    supervision: [{ tag: 'Supervision_Trip' }] },
  { number: 4, name: 'Step4', init: false, title: '气缸推出',
    actions: [{ qualifier: 'N', tag: 'Valve_1' }],
    interlock: [{ tag: 'Interlock_Trip', negated: true }],
    supervision: [{ tag: 'Supervision_Trip' }] },
  { number: 5, name: 'Step5', init: false, title: '选择分支 B：快速加工（电机 3 运行）',
    actions: [{ qualifier: 'N', tag: 'Motor_3' }],
    interlock: [{ tag: 'Interlock_Trip', negated: true }],
    supervision: [{ tag: 'Supervision_Trip' }] },
  { number: 6, name: 'Step6', init: false, title: '并行分支 A：冷却风机运行',
    actions: [{ qualifier: 'N', tag: 'Fan_1' }],
    interlock: [{ tag: 'Interlock_Trip', negated: true }],
    supervision: [{ tag: 'Supervision_Trip' }] },
  { number: 7, name: 'Step7', init: false, title: '并行分支 B：润滑泵运行',
    actions: [{ qualifier: 'N', tag: 'Pump_1' }],
    interlock: [{ tag: 'Interlock_Trip', negated: true }],
    supervision: [{ tag: 'Supervision_Trip' }] },
  { number: 8, name: 'Step8', init: false, title: '并行分支 A 结束步：保持冷却，等待汇合',
    actions: [{ qualifier: 'N', tag: 'Fan_1' }],
    interlock: [{ tag: 'Interlock_Trip', negated: true }],
    supervision: [{ tag: 'Supervision_Trip' }] },
  { number: 9, name: 'Step9', init: false, title: '并行分支 B 结束步：保持润滑，等待汇合',
    actions: [{ qualifier: 'N', tag: 'Pump_1' }],
    interlock: [{ tag: 'Interlock_Trip', negated: true }],
    supervision: [{ tag: 'Supervision_Trip' }] },
  { number: 10, name: 'Step10', init: false, title: '收尾：复位全部输出',
    actions: [
      { qualifier: 'R', tag: 'Motor_1' }, { qualifier: 'R', tag: 'Motor_2' },
      { qualifier: 'R', tag: 'Motor_3' }, { qualifier: 'R', tag: 'Valve_1' },
      { qualifier: 'R', tag: 'Fan_1' }, { qualifier: 'R', tag: 'Pump_1' },
      { qualifier: 'R', tag: 'Run_Lamp' },
    ],
    interlock: [{ tag: 'Interlock_Trip', negated: true }],
    supervision: [{ tag: 'Supervision_Trip' }] },
];

const transitions = [
  { number: 1, name: 'Trans1', comment: '启动按钮 Start_Button', contacts: [{ tag: 'Start_Button' }] },
  { number: 2, name: 'Trans2', comment: '选择分支 A（正常模式）：送料到位 Sensor_1 且 非 Mode_Fast 且 未按停止',
    contacts: [{ tag: 'Sensor_1' }, { tag: 'Mode_Fast', negated: true }, { tag: 'Stop_Button', negated: true }] },
  { number: 3, name: 'Trans3', comment: '选择分支 B（快速模式）：送料到位 Sensor_1 且 Mode_Fast 且 未按停止',
    contacts: [{ tag: 'Sensor_1' }, { tag: 'Mode_Fast' }, { tag: 'Stop_Button', negated: true }] },
  { number: 4, name: 'Trans4', comment: '选择分支 A 加工完成 Sensor_2：进入汇合', contacts: [{ tag: 'Sensor_2' }] },
  { number: 5, name: 'Trans5', comment: '选择分支 B 加工完成 Sensor_2：进入汇合', contacts: [{ tag: 'Sensor_2' }] },
  { number: 6, name: 'Trans6', comment: '气缸到位 Sensor_3：进入并行分支', contacts: [{ tag: 'Sensor_3' }] },
  { number: 7, name: 'Trans7', comment: '并行分支 A：冷却到位 Sensor_4', contacts: [{ tag: 'Sensor_4' }] },
  { number: 8, name: 'Trans8', comment: '并行分支 B：润滑到位 Sensor_5', contacts: [{ tag: 'Sensor_5' }] },
  { number: 9, name: 'Trans9', comment: '两路并行全部完成 且 未按停止：进入收尾步', contacts: [{ tag: 'Stop_Button', negated: true }] },
  { number: 10, name: 'Trans10', comment: '复位按钮回到初始步', contacts: [{ tag: 'Reset_Button' }] },
];

// Branch nodes: one alternative branch (选择分支) and one simultaneous branch (并行分支).
// Begin and end are separate <Branch> entries; the numbers are just ids that <BranchRef>
// elements point at - the wiring in <Connections> defines the topology.
const branches = [
  { number: 1, type: 'AltBegin', cardinality: 2 },   // 选择分支：分叉
  { number: 2, type: 'AltEnd',   cardinality: 2 },   // 选择分支：汇合
  { number: 3, type: 'SimBegin', cardinality: 2 },   // 并行分支：分叉
  { number: 4, type: 'SimEnd',   cardinality: 2 },   // 并行分支：汇合
];

// Sequential links are "Direct"; the link that closes the cycle back to the initial step
// must be "Jump" - otherwise TIA reports "the sequencer does not start with a step"
// (verified against real TIA exports, e.g. refs/exported/钻孔系统自动程序.xml).
const connections = [
  // 初始步 -> 送料
  [stepRef(1),      transRef(1),    'Direct'],
  [transRef(1),     stepRef(2),     'Direct'],
  // 送料 -> 选择分支（AltBegin）：分叉节点直接接在步后面，每条支路各自带转换条件
  [stepRef(2),      branchIn(1, 0), 'Direct'],
  [branchOut(1, 0), transRef(2),    'Direct'],
  [transRef(2),     stepRef(3),     'Direct'],
  [branchOut(1, 1), transRef(3),    'Direct'],
  [transRef(3),     stepRef(5),     'Direct'],
  // 选择分支汇合（AltEnd）：每条支路末步各带转换进入汇合节点，汇合后直接进入下一步
  [stepRef(3),      transRef(4),    'Direct'],
  [transRef(4),     branchIn(2, 0), 'Direct'],
  [stepRef(5),      transRef(5),    'Direct'],
  [transRef(5),     branchIn(2, 1), 'Direct'],
  [branchOut(2, 0), stepRef(4),     'Direct'],
  // 气缸到位 -> 并行分支（SimBegin）：分叉前一个公共转换，分叉后直接到各支路首步
  [stepRef(4),      transRef(6),    'Direct'],
  [transRef(6),     branchIn(3, 0), 'Direct'],
  [branchOut(3, 0), stepRef(6),     'Direct'],
  [branchOut(3, 1), stepRef(7),     'Direct'],
  // 并行分支汇合（SimEnd）：每条支路的结束条件放在"支路末步之前的转换"上，
  // 支路末步（结束步）直接接汇合节点，汇合后再由一个公共转换进入收尾步
  [stepRef(6),      transRef(7),    'Direct'],
  [transRef(7),     stepRef(8),     'Direct'],
  [stepRef(7),      transRef(8),    'Direct'],
  [transRef(8),     stepRef(9),     'Direct'],
  [stepRef(8),      branchIn(4, 0), 'Direct'],
  [stepRef(9),      branchIn(4, 1), 'Direct'],
  [branchOut(4, 0), transRef(9),    'Direct'],
  [transRef(9),     stepRef(10),    'Direct'],
  // 收尾 -> 跳回初始步
  [stepRef(10),     transRef(10),   'Direct'],
  [transRef(10),    stepRef(1),     'Jump'],
].map(([f, t, l]) => connection(f, t, l)).join('\n');

const xml = `<?xml version="1.0" encoding="utf-8"?>
<Document>
  <Engineering version="V20" />
  <SW.Blocks.FB ID="0">
    <AttributeList>
      <AutoNumber>false</AutoNumber>
      <GraphVersion>${GRAPH_VERSION}</GraphVersion>
      ${interfaceXml}
      <Name>${BLOCK_NAME}</Name>
      <Namespace />
      <Number>${BLOCK_NUMBER}</Number>
      <ProgrammingLanguage>GRAPH</ProgrammingLanguage>
      <SetENOAutomatically>false</SetENOAutomatically>
    </AttributeList>
    <ObjectList>
      <MultilingualText ID="1" CompositionName="Comment">
        <ObjectList>
          <MultilingualTextItem ID="2" CompositionName="Items">
            <AttributeList>
              <Culture>zh-CN</Culture>
              <Text />
            </AttributeList>
          </MultilingualTextItem>
        </ObjectList>
      </MultilingualText>
      <SW.Blocks.CompileUnit ID="3" CompositionName="CompileUnits">
        <AttributeList>
          <NetworkSource><Graph xmlns="http://www.siemens.com/automation/Openness/SW/NetworkSource/Graph/v5">
    <PreOperations />
    <Sequence>
      <Title>${mlt('顺序控制示例：启动 → 送料 → 选择分支（正常/快速加工）→ 气缸 → 并行分支（冷却+润滑）→ 收尾 → 复位回初始步')}</Title>
      <Comment>${mlt('GRAPH 顺序功能图示例（CPU 1511-1 PN）：含 1 个选择分支（AltBegin/AltEnd，按 Mode_Fast 二选一）与 1 个并行分支（SimBegin/SimEnd，冷却风机与润滑泵同时运行）。每步互锁 Interlock_Trip 为 1 时禁止本步动作，监控 Supervision_Trip 为 1 时触发监控故障。')}</Comment>
      <Steps>
${steps.map(stepXml).join('\n')}
      </Steps>
      <Transitions>
${transitions.map(transitionXml).join('\n')}
      </Transitions>
      <Branches>
${branches.map(b => `        <Branch Number="${b.number}" Type="${b.type}" Cardinality="${b.cardinality}" />`).join('\n')}
      </Branches>
      <Connections>
${connections}
      </Connections>
    </Sequence>
    <PostOperations />
    <AlarmsSettings>
      <AlarmSupervisionCategories>
        <AlarmSupervisionCategory Id="1" DisplayClass="0" />
        <AlarmSupervisionCategory Id="2" DisplayClass="0" />
        <AlarmSupervisionCategory Id="3" DisplayClass="0" />
        <AlarmSupervisionCategory Id="4" DisplayClass="0" />
        <AlarmSupervisionCategory Id="5" DisplayClass="0" />
        <AlarmSupervisionCategory Id="6" DisplayClass="0" />
        <AlarmSupervisionCategory Id="7" DisplayClass="0" />
        <AlarmSupervisionCategory Id="8" DisplayClass="0" />
      </AlarmSupervisionCategories>
      <AlarmInterlockCategory Id="1" />
      <AlarmSubcategory1Interlock Id="0" />
      <AlarmSubcategory2Interlock Id="0" />
      <AlarmCategorySupervision Id="1" />
      <AlarmSubcategory1Supervision Id="0" />
      <AlarmSubcategory2Supervision Id="0" />
      <AlarmWarningCategory Id="2" />
      <AlarmSubcategory1Warning Id="0" />
      <AlarmSubcategory2Warning Id="0" />
    </AlarmsSettings>
  </Graph></NetworkSource>
          <ProgrammingLanguage>GRAPH</ProgrammingLanguage>
        </AttributeList>
        <ObjectList>
          <MultilingualText ID="4" CompositionName="Comment">
            <ObjectList>
              <MultilingualTextItem ID="5" CompositionName="Items">
                <AttributeList>
                  <Culture>zh-CN</Culture>
                  <Text>GRAPH 顺序控制示例</Text>
                </AttributeList>
              </MultilingualTextItem>
            </ObjectList>
          </MultilingualText>
          <MultilingualText ID="6" CompositionName="Title">
            <ObjectList>
              <MultilingualTextItem ID="7" CompositionName="Items">
                <AttributeList>
                  <Culture>zh-CN</Culture>
                  <Text>顺序控制示例</Text>
                </AttributeList>
              </MultilingualTextItem>
            </ObjectList>
          </MultilingualText>
        </ObjectList>
      </SW.Blocks.CompileUnit>
      <MultilingualText ID="8" CompositionName="Title">
        <ObjectList>
          <MultilingualTextItem ID="9" CompositionName="Items">
            <AttributeList>
              <Culture>zh-CN</Culture>
              <Text />
            </AttributeList>
          </MultilingualTextItem>
        </ObjectList>
      </MultilingualText>
    </ObjectList>
  </SW.Blocks.FB>
</Document>
`;

mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, xml, 'utf8');
console.log(JSON.stringify({
  generated: outPath,
  interfaceSource: refPath,
  block: BLOCK_NAME,
  language: 'GRAPH',
  graphVersion: GRAPH_VERSION,
  steps: steps.length,
  transitions: transitions.length,
  branches: branches.map(b => `${b.type}(${b.number}/Cardinality=${b.cardinality})`),
  connections: connections.split('<Connection>').length - 1,
  coils: { TrCoil: transitions.length, IlCoil: steps.length, SvCoil: steps.length },
  bytes: Buffer.byteLength(xml, 'utf8'),
}, null, 2));
