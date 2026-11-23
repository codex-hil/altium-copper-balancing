from pathlib import Path
from altium_monkey import AltiumPcbDoc
from collections import Counter
import json,hashlib,dataclasses
r=Path(__file__).resolve().parents[1];e=r/'evidence';prefix='CBAL_7F93C2A1_'
def norm(x):
 if isinstance(x,(str,int,float,bool,type(None))):return x
 if isinstance(x,bytes):return x.hex()
 if isinstance(x,dict):return {k:norm(v) for k,v in x.items() if str(k) not in ('DATE','TIME','FILENAME','used_by_prims') and not str(k).endswith('USEDBYPRIMS') and not str(k).startswith('VP.')}
 if isinstance(x,(list,tuple)):return [norm(v) for v in x]
 if dataclasses.is_dataclass(x):return norm(dataclasses.asdict(x))
 return {k:norm(v) for k,v in vars(x).items() if not k.startswith('_')}
def owned(p):return [x for x in p.regions if x.properties.get('NAME','').startswith(prefix)]
a=AltiumPcbDoc.from_file(r/'TestBoard.PcbDoc');b=AltiumPcbDoc.from_file(e/'Native-generated.PcbDoc');c=AltiumPcbDoc.from_file(e/'Native-regenerated.PcbDoc');d=AltiumPcbDoc.from_file(e/'Native-removed.PcbDoc')
assert not owned(a)
assert Counter(x.layer for x in owned(b))=={1:108,2:108,3:108,32:108}
assert Counter(x.layer for x in owned(c))=={2:108}
assert not owned(d)
for p in (b,c,d):
 for x in owned(p):assert x.net_index is None and x.kind==0 and x.hole_count==0 and len(x.outline_vertices)==4 and x.layer not in (39,40)
 for k in ('board','nets','rules','tracks','arcs','pads','vias','fills','polygons','regions','shapebased_regions','board_regions','union_name_records'):
  x=getattr(a,k);y=getattr(p,k)
  if k in ('regions','shapebased_regions'):
   x=[v for v in x if not v.properties.get('NAME','').startswith(prefix)]
   y=[v for v in y if not v.properties.get('NAME','').startswith(prefix)]
  assert norm(x)==norm(y),k
report={'status':'PASS','generated':{'1':108,'2':108,'3':108,'32':108},'regenerated':{'2':108},'removed':0,'negative_planes':0,'net_assignment':'all None','original_modeled_objects':'preserved; board DATE/TIME/FILENAME, viewport and UsedByPrims caches excluded','sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (r/'TestBoard.PcbDoc',e/'Native-generated.PcbDoc',e/'Native-regenerated.PcbDoc',e/'Native-removed.PcbDoc')}}
(e/'native-verification.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
