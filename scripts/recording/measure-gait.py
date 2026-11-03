"""Read-only gait evidence: feet relative to the actor and to each other, not world foot stillness."""
from pathlib import Path
import json, math
import numpy as np

root = Path(__file__).resolve().parents[2]
recording = json.loads((root/'runs/videos/locomotion-recording.json').read_text())
phases = ['forward', 'lateral', 'turn']

def rows(folder, role):
    result = []
    for line in (folder/(role+'-locomotion.jsonl')).read_text(encoding='utf-8-sig').splitlines():
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if row.get('type') == 'sample' and row['phase'] in phases:
            result.append(row)
    return result

def measure(folder, role, who):
    data = rows(folder, role)
    result = {}
    for phase in phases:
        moving = [r for r in data if r['phase'] == phase and r[who]['speed'] > 25]
        feet, pairs = {name: [] for name in ['foot_l', 'foot_r']}, []
        for row in moving:
            actor = row[who]
            yaw = math.radians(actor['yaw'])
            for name in feet:
                foot = actor['feet'][name]
                x, y = foot['x']-actor['x'], foot['y']-actor['y']
                feet[name].append([x*math.cos(yaw)+y*math.sin(yaw), -x*math.sin(yaw)+y*math.cos(yaw), foot['z']-actor['z']])
            pairs.append(np.array(feet['foot_l'][-1])-feet['foot_r'][-1])
        if len(pairs) < 5:
            result[phase] = {'samples': len(pairs), 'interFootMotionAboveThreshold': False}
            continue
        pair = np.asarray(pairs)
        pair_range = np.ptp(pair, axis=0)
        result[phase] = {
            'samples': len(pairs),
            'rootRelativeRangeCm': {k: np.ptp(v, axis=0).tolist() for k, v in feet.items()},
            'interFootRangeCm': pair_range.tolist(),
            'interFootPathCm': float(np.linalg.norm(np.diff(pair, axis=0), axis=1).sum()),
            'interFootMotionAboveThreshold': bool(max(pair_range[:2]) > 15),
            'lastInputMagnitudeMedian': float(np.median([math.hypot(r[who]['lastInput']['X'],r[who]['lastInput']['Y']) for r in moving])),
            'actualAccelerationMedian': float(np.median([math.hypot(r[who]['acceleration']['X'],r[who]['acceleration']['Y']) for r in moving])),
            'nativeDriverInputMedian': float(np.median([math.hypot(r[who].get('nativeMoveInput',{}).get('X',0),r[who].get('nativeMoveInput',{}).get('Y',0)) for r in moving])),
            'animationHasAccelerationFraction': float(np.mean([r[who]['animation']['hasAcceleration'] for r in moving])),
            'animationRateScales': sorted(set(r[who]['animation'].get('rateScale',-1) for r in moving)),
            'actorVsCMCVelocityMaxError': max((math.hypot(r[who]['vx']-r[who]['cmVelocity']['X'],r[who]['vy']-r[who]['cmVelocity']['Y']) for r in moving if 'cmVelocity' in r[who]), default=None),
        }
    return result

out = {'baseline': measure(root/'runs/locomotion-game-1793697633394','host','ghost'),
       'rejected': measure(root/'runs/locomotion-game-1793704513710','host','ghost'),
       'currentHost': measure(Path(recording['run']),'host','ghost'),
       'currentGuest': measure(Path(recording['run']),'guest','player'),
       'run': recording['run'], 'video': recording['outputPath'],
       'metricCaveat': 'Inter-foot motion excludes common whole-body translation; thresholds alone cannot establish visually natural gait.',
       'visualReview': 'pending'}
(root/'runs/videos/gait-recovery-feet.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
print(json.dumps(out,indent=2))
