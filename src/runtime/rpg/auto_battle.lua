-- MZ Game_Actor.makeAutoBattleActions. Prepared action metadata stays in the
-- shared resolver; this module only selects slots and advances a private RNG.
return function(deps)
 local RNG=deps['runtime.core.rng'];local M={};local LIMIT=100000
 local function fail(code,reason)error({severity='error',code=code,reason=reason,profile='mz-1.10.0'},0)end
 local function plain(v)if type(v)~='table'or getmetatable(v)~=nil then fail('E_AUTO_BATTLE_SHAPE','Expected plain table')end end
 local function integer(v,lo,hi)if type(v)~='number'or v~=v or v%1~=0 or v<lo or v>hi then fail('E_AUTO_BATTLE_NUMBER','Integer outside supported range')end;return v*1.0 end
 local function dense(v)local n,high=0,0;plain(v);for k in next,v do integer(k,1,LIMIT);n=n+1;high=math.max(high,k)end;if n~=high then fail('E_AUTO_BATTLE_SHAPE','Expected dense array')end;return n end
 function M.select(q,ctx,actions)
  plain(q);local allowed={battleId=true,subjectRef=true,actionCount=true,partyRefs=true,troopRefs=true,rngState=true,variables=true}
  for k in next,q do if not allowed[k]then fail('E_AUTO_BATTLE_SHAPE','Unknown request field')end end
  if type(q.battleId)~='string'or #q.battleId<1 or #q.battleId>128 then fail('E_AUTO_BATTLE_REFERENCE','Invalid battle ID')end
  plain(q.subjectRef);if q.subjectRef.kind~='actor'then fail('E_AUTO_BATTLE_REFERENCE','Auto battle requires an actor')end
  for k in next,q.subjectRef do if k~='kind'and k~='id'then fail('E_AUTO_BATTLE_REFERENCE','Unknown actor reference field')end end
  local subject={kind='actor',id=integer(q.subjectRef.id,1,9007199254740991)};local count=integer(q.actionCount,0,1000)
  local members=dense(q.partyRefs)+dense(q.troopRefs);if members>1000 then fail('E_AUTO_BATTLE_BUDGET','Member budget exceeded')end
  plain(ctx);plain(actions);for _,name in ipairs({'canUse','evaluate'})do if type(actions[name])~='function'then fail('E_AUTO_BATTLE_CAPABILITY','Prepared action '..name..' required')end end
  if type(ctx.query)~='function'then fail('E_AUTO_BATTLE_CAPABILITY','Read-only query required')end
  local rng=RNG.restore(q.rngState).snapshot();local initial=rng.draws;local slots={}
  for slot=1,count do
   local s=ctx.query(subject);local size=dense(s.skills)
   if count*(size+1)*(members*2+1)>LIMIT then fail('E_AUTO_BATTLE_BUDGET','Evaluation work budget exceeded')end
   local attack=integer(s.traits.attackSkillId(),1,9007199254740991);local list={{kind='skill',id=attack}}
   for _,id in ipairs(s.skills)do local r={kind='skill',id=integer(id,1,9007199254740991)};if actions.canUse({actionRef=r,subjectRef=subject,inBattle=true},ctx).ok then list[#list+1]=r end end
   local best;slots[slot]=false
   for _,r in ipairs(list)do
    local out=actions.evaluate({battleId=q.battleId,actionRef=r,subjectRef=subject,inBattle=true,partyRefs=q.partyRefs,troopRefs=q.troopRefs,rngState=rng,variables=q.variables},ctx)
    if not out.ok then fail('E_AUTO_BATTLE_EVALUATE','Prepared evaluation failed')end;rng=out.rngState
    if not out.notANumber and (best==nil or out.value>best)then
     best=out.value;slots[slot]={actionRef={kind='skill',id=r.id},targetIndex=out.targetIndex,isAttack=r.id==attack,forcing=false}
    end
   end
  end
  local final=RNG.restore(rng).snapshot();return{ok=true,actionSlots=slots,rngState=final,drawsUsed=final.draws-initial}
 end
 return M
end
