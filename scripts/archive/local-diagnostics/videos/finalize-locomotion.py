import pathlib,json
b=pathlib.Path('D:/pb0online/runs/videos');root=b.parent.parent
v=json.loads((b/'locomotion-validation.json').read_text(encoding='utf-8'))
r=pathlib.Path(v['run']);host=v['roles']['host']['phases'];guest=v['roles']['guest']['phases']
rows=[]
for line in (r/'host-locomotion.jsonl').read_text(encoding='utf-8').splitlines():
 try:x=json.loads(line)
 except json.JSONDecodeError:continue
 if x['type']=='sample' and x['phase'] in ['forward','lateral','turn'] and x.get('target',{}).get('Speed',0)>25:rows.append(x)
matching=sum(x['ghost']['animation']['gait']==x['target'].get('Gait') for x in rows)
stops=all(host[p]['tailSpeedMax']==0 and host[p]['tailTravelCm']==0 for p in ['stop-one','stop-two','stop-three'])
steps=all(host[p]['travelCm']>15 and host[p]['footPlantFraction']>.35 and host[p]['lowerFootSpeedRatioMedian']<.4 for p in ['forward','lateral','turn'])
events={}
for role in ['host','guest']:
 obs=[]
 for line in (r/(role+'-observations.jsonl')).read_text().splitlines():
  try:obs.append(json.loads(line))
  except json.JSONDecodeError:pass
 events[role]={'localAttacks':sum(x['type']=='local_attack' and x.get('ok') for x in obs),'nativeRemoteMoves':sum(x['type']=='remote_move_applied' for x in obs)}
assert matching==len(rows) and len(rows)>50 and stops and steps
assert events['guest']['localAttacks']==1 and events['host']['nativeRemoteMoves']>=1
for role in v['roles'].values():
 role.pop('nativeRemoteControlledAll',None)
 role['remoteMotor']='existing native CharacterMovement with analog input, bounded tracking and native gait replication'
v['validationComplete']=True
v['acceptance']={'boundedWalkingPrototypePassed':True,'gaitSamples':len(rows),'gaitSamplesMatching':matching,'allThreeStopsHaveZeroResidualDisplacement':stops,'realAttackEvents':events,'manualFrameReview':'Reviewed current decoded frames and clear side-by-side real host/guest viewports. Both subjects and their feet visible.','limits':['Remote speed still differs slightly from local, with residual follow lag/offset. Natural walking is improved; exact pose/frame identity is not claimed.','Only short forward/lateral/stop/turn and one-attack sequence checked. Sprint, slopes, evasive skills and WAN movement not covered.','No repeat of the already-passed attack/block/Perfect combat assertions.']}
(b/'locomotion-validation.json').write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf-8')
summary={'Schema':1,'Date':'2026-11-03','Task':'Real guest Enhanced Input and remote walking gait/stop fix','Passed':True,'InputAction':'/SGameLocomotionDriver/Input/IA_JoystickMoveInput','TwoRealGames':True,'ExistingSaveIsolationProofReused':True,'GameBridgeAndEasyTierUnchanged':True,'ExistingNetworkStateHzUnchanged':True,'Changes':['Authoritative optional gait appended to P snapshot, older readers ignore trailing field','Native remote animation uses that gait after its normal locomotion state update','Analog CharacterMovement speed matching, bounded correction, native turn pivot calibration','Stationary input/velocity latch prevents repeated minimum-speed correction'],'Measurements':{'GaitMatched':matching,'GaitSamples':len(rows),'RemoteStopResidualCm':[host[p]['tailTravelCm'] for p in ['stop-one','stop-two','stop-three']],'RemoteFootPlantFraction':{p:host[p]['footPlantFraction'] for p in ['forward','lateral','turn']},'RemoteLowerFootSpeedRatioMedian':{p:host[p]['lowerFootSpeedRatioMedian'] for p in ['forward','lateral','turn']},'RemoteMaxTurnPositionStepCm':host['turn']['maxPositionStepCm']},'Recording':{'DurationSeconds':v['recording']['seconds'],'Resolution':[1920,1080],'FPS':60,'RealHostAndGuestSideBySide':True,'RenderDropped':v['obs']['renderDropped'],'EncoderDropped':v['obs']['encodeDropped'],'StoredLocallyOnly':True},'Limit':'Small remaining tracking speed/position error; no sprint/slopes/WAN acceptance claimed.'}
(root/'verification/locomotion-20261103.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'video':v['video'],'seconds':v['recording']['seconds'],'gait':str(matching)+'/'+str(len(rows)),'remoteStopCm':summary['Measurements']['RemoteStopResidualCm'],'events':events},indent=2))