import fs from 'node:fs';
import assert from 'node:assert/strict';
import {networks} from './build-fixed-lad.mjs';
class Scan {
 constructor(){this.bits={};this.timers={};this.events=[];this.previous='000';}
 scan(t,start,stop){this.bits['M0.0']=start;this.bits['M0.1']=stop;
 const flow=(els,power=true)=>{for(const e of els){if(e.kind==='contact')power=power&&(e.nc?!this.bits[e.addr]:!!this.bits[e.addr]);else if(e.kind==='or')power=e.branches.some(b=>flow(b,power));else if(e.kind==='timer'){const tm=this.timers[e.name]??={begin:null,q:false};if(!power){tm.begin=null;tm.q=false;}else{tm.begin??=t;tm.q=t-tm.begin>=2000;}power=tm.q;}else if(e.mode==='Coil')this.bits[e.addr]=power;else if(power)this.bits[e.addr]=e.mode==='SCoil';}return power;};
 for(const [,els] of networks)flow(els);
 const out=['Q0.0','Q0.1','Q0.2'].map(a=>this.bits[a]?'1':'0').join('');if(out!==this.previous){this.events.push({t,out});this.previous=out;}return out;
 }
}
const cases=[
 {name:'full_start_pulse_stop_pulse',end:11000,start:t=>t===0,stop:t=>t===5000,expect:[[0,'100'],[2000,'110'],[4000,'111'],[5000,'110'],[7000,'100'],[9000,'000']]},
 {name:'stop_during_first_motor',end:5000,start:t=>t===0,stop:t=>t===1000,expect:[[0,'100'],[1000,'000']]},
 {name:'stop_during_second_motor',end:7000,start:t=>t===0,stop:t=>t===3000,expect:[[0,'100'],[2000,'110'],[3000,'100'],[5000,'000']]},
 {name:'held_start_no_auto_restart',end:12000,start:()=>true,stop:t=>t===5000,expect:[[0,'100'],[2000,'110'],[4000,'111'],[5000,'110'],[7000,'100'],[9000,'000']]},
 {name:'simultaneous_start_stop',end:5000,start:t=>t===0,stop:t=>t===0,expect:[]},
 {name:'restart_after_stop',end:16000,start:t=>t===0||t===10000,stop:t=>t===5000,expect:[[0,'100'],[2000,'110'],[4000,'111'],[5000,'110'],[7000,'100'],[9000,'000'],[10000,'100'],[12000,'110'],[14000,'111']]},
 {name:'ignore_start_during_stop',end:12000,start:t=>t===0||t===6000,stop:t=>t===5000,expect:[[0,'100'],[2000,'110'],[4000,'111'],[5000,'110'],[7000,'100'],[9000,'000']]},
 {name:'held_stop_blocks_restart',end:12000,start:t=>t===0||t===10000,stop:t=>t>=5000,expect:[[0,'100'],[2000,'110'],[4000,'111'],[5000,'110'],[7000,'100'],[9000,'000']]},
];
const results=[];
for(const tc of cases){const s=new Scan;for(let t=0;t<=tc.end;t+=10)s.scan(t,tc.start(t),tc.stop(t));assert.deepEqual(s.events,tc.expect.map(([t,out])=>({t,out})),tc.name);results.push({name:tc.name,passed:true,events:s.events});}
// Every stop offset across startup, including timer boundary scans.
for(let stopAt=0;stopAt<=5000;stopAt+=10){const s=new Scan;for(let t=0;t<=stopAt+5000;t+=10){const before=s.previous;s.scan(t,t===0,t===stopAt);if(t>=stopAt)assert.ok(parseInt(s.previous,2)<=parseInt(before,2),'No motor may turn on during stopping');}assert.equal(s.previous,'000');}
const report={date:'2026-10-06',method:'LAD network IR scan simulation, 10 ms step; not PLCSIM',scenarios:results,stopOffsets:501,passed:true};
fs.writeFileSync(new URL('../logs/logic-test.json',import.meta.url),JSON.stringify(report,null,2));console.log(JSON.stringify({passed:true,scenarios:results.length,stopOffsets:501}));
