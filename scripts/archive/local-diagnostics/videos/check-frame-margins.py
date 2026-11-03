import pathlib,json
b=pathlib.Path('runs/videos');m=json.loads((b/'quality-recording-output.json').read_text());r=pathlib.Path(m['run'])
s=[json.loads(x) for x in (r/'scene-observations.jsonl').read_text().splitlines()];s=[x for x in s if x['capture']]
out=[]
for x in s:
 if not x['framed']: out.append({k:x[k] for k in ['time','phase','player','ghost','distance']})
print(json.dumps({'badMarginFrames':len(out),'actuallyOutsideScreen':sum(any(a[k]<0 or a[k]>1 for a in [x['player'],x['ghost']] for k in ['minX','maxX','minY','maxY']) for x in s),'badSamples':out[:3]+out[-3:]},indent=2))