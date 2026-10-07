-- Faithful AuroraCore.js rules port. All data and type multipliers are AOT Lua.
-- Moves passed to attack/turn use the source's ZERO-based index (-1=Struggle).
return function() local make = function(data, rng)
 local C={data=data,rng=rng or math.random}
 local function has(xs,x)for _,v in ipairs(xs)do if v==x then return true end end;return false end
 local function append(xs,ys)for _,v in ipairs(ys)do xs[#xs+1]=v end end
 local function count(level)return level<8 and 1 or level<16 and 2 or level<25 and 3 or 4 end
 function C.spec(id)return assert(data.species[tostring(id)],'Unknown Aurora species '..tostring(id))end
 function C.move(name)return assert(data.moves[name],'Unknown Aurora move '..tostring(name))end
 function C.effect(t,types)
  local value=1;local row=data.typeChart[t] or {}
  for _,other in ipairs(types)do local m=row[other];value=value*(m==nil and 1 or m)end
  return value
 end
 function C.stats(p)
  local b,l=C.spec(p.id).base,p.level
  return{hp=math.floor(b[1]*2*l/100)+l+15,atk=math.floor(b[2]*2*l/100)+8,
   def=math.floor(b[3]*2*l/100)+8,spd=math.floor(b[4]*2*l/100)+8}
 end
 function C.create(id,level)
  local names={'撞击'};local learn=C.spec(id).learn
  for i=1,math.min(#learn,count(level))do if not has(names,learn[i])then names[#names+1]=learn[i]end end
  while #names>4 do table.remove(names,1)end
  local p={id=id,level=level,xp=0,hp=1,status='',sleep=0,moves={}}
  for _,name in ipairs(names)do p.moves[#p.moves+1]={name=name,pp=C.move(name).pp}end
  p.hp=C.stats(p).hp;return p
 end
 function C.heal(p)
  p.hp=C.stats(p).hp;p.status='';p.sleep=0
  for _,m in ipairs(p.moves)do m.pp=C.move(m.name).pp end
 end
 function C.state()
  return{v=1,party={},box={},seen={},caught={},badges={},flags={},
   bag={ball=20,great=0,ultra=0,potion=8,super=0,revive=2,cure=3},money=1800,
   steps=0,lastCenter=1,league=0,chapter=0,playSeconds=0}
 end
 function C.record(s,id,caught)
  if not has(s.seen,id)then s.seen[#s.seen+1]=id end
  if caught and not has(s.caught,id)then s.caught[#s.caught+1]=id end
 end
 function C.add(s,p)
  if #s.party>=6 and #s.box>=120 then return false end
  C.record(s,p.id,true);local into=#s.party<6 and s.party or s.box;into[#into+1]=p;return true
 end
 function C.exp(p,amount)
  local logs={};p.xp=p.xp+amount
  while p.level<65 and p.xp>=p.level*12 do
   p.xp=p.xp-p.level*12;local before=C.stats(p).hp;p.level=p.level+1
   p.hp=math.min(C.stats(p).hp,p.hp+C.stats(p).hp-before)
   logs[#logs+1]=C.spec(p.id).name..' 升至 Lv.'..p.level
   local sp=C.spec(p.id)
   if sp.evolve and sp.evolve~=0 and p.level>=sp.evolveLevel then
    p.id=sp.evolve;logs[#logs+1]=sp.name..' 进化成 '..C.spec(p.id).name..'！';C.heal(p)
   end
   local learn=C.spec(p.id).learn
   for i=1,math.min(#learn,count(p.level))do
    local n=learn[i];local found=false
    for _,m in ipairs(p.moves)do if m.name==n then found=true;break end end
    if not found then
     if #p.moves>=4 then table.remove(p.moves,1)end
     p.moves[#p.moves+1]={name=n,pp=C.move(n).pp};logs[#logs+1]='学会了 '..n
    end
   end
  end
  return logs
 end
 function C.damage(a,b,m)
  local eff=C.effect(m.type,C.spec(b.id).types);if eff==0 then return 0 end
  local sa,sb=C.stats(a),C.stats(b)
  return math.max(1,math.floor(((2*a.level/5+2)*m.power*sa.atk/sb.def/50+2)
   *(has(C.spec(a.id).types,m.type) and 1.5 or 1)*eff*(.85+C.rng()*.15)*(a.status=='灼伤' and .7 or 1)))
 end
 function C.attack(a,b,index)
  local logs={};local used=a.moves[index+1]
  local m=used and used.pp>0 and C.move(used.name) or C.move('挣扎');local name=C.spec(a.id).name
  if a.hp<=0 then return logs end
  if a.status=='睡眠'then
   a.sleep=a.sleep-1;if a.sleep>0 then return{name..' 仍在睡觉'}end
   a.status='';logs[#logs+1]=name..' 醒来了'
  end
  if a.status=='麻痹' and C.rng()<.25 then return{name..' 因麻痹无法行动'}end
  if used and used.pp>0 then used.pp=used.pp-1 end
  logs[#logs+1]=name..' 使用 '..m.name
  if C.rng()*100>m.acc*(a.accuracy or 1)then logs[#logs+1]='招式没有命中';return logs end
  if m.effect=='heal'then
   local h=math.min(math.ceil(C.stats(a).hp*.5),C.stats(a).hp-a.hp)
   a.hp=a.hp+h;logs[#logs+1]='恢复 '..h..' HP';return logs
  end
  if m.effect=='protect'then a.protect=true;return logs end
  if b.protect then logs[#logs+1]='对手守住了攻击';return logs end
  if m.effect=='accuracy'then b.accuracy=math.max(.55,(b.accuracy or 1)*.85);return logs end
  if m.effect=='slow'then b.slow=true;return logs end
  if m.power~=0 and m.power~=nil then
   local d=C.damage(a,b,m);b.hp=math.max(0,b.hp-d);local eff=C.effect(m.type,C.spec(b.id).types)
   logs[#logs+1]='造成 '..d..' 伤害'..(eff>1 and '，效果绝佳！' or eff==0 and '，没有效果' or eff<1 and '，效果不理想' or '')
   if m.effect=='recoil'then a.hp=math.max(0,a.hp-math.max(1,math.floor(d/4)))end
  end
  if b.hp>0 and b.status=='' and C.effect(m.type,C.spec(b.id).types)>0 then
   local status=''
   if m.effect=='sleep'then status='睡眠'end
   if m.effect=='paralysis' and not has(C.spec(b.id).types,'电')then status='麻痹'end
   if m.effect=='para20' and C.rng()<.2 and not has(C.spec(b.id).types,'电')then status='麻痹'end
   if m.effect=='burn20' and C.rng()<.2 and not has(C.spec(b.id).types,'火')then status='灼伤'end
   if m.effect=='poison30' and C.rng()<.3 and not has(C.spec(b.id).types,'毒')then status='中毒'end
   if status~=''then b.status=status;b.sleep=2+math.floor(C.rng()*2);logs[#logs+1]=C.spec(b.id).name..' 陷入'..status end
  end
  return logs
 end
 function C.endTurn(p)
  if p.hp>0 and (p.status=='中毒' or p.status=='灼伤')then
   local d=math.max(1,math.floor(C.stats(p).hp/10));p.hp=math.max(0,p.hp-d)
   return{C.spec(p.id).name..' 受到'..p.status..'伤害 '..d}
  end
  return{}
 end
 function C.speed(p)return C.stats(p).spd*(p.status=='麻痹' and .5 or 1)*(p.slow and .65 or 1)end
 function C.ai(p,foe)
  local best,score=-1,-1
  for i,m in ipairs(p.moves)do if m.pp>0 then
   local v=C.move(m.name);local x=v.power*C.effect(v.type,C.spec(foe.id).types)*(has(C.spec(p.id).types,v.type) and 1.5 or 1)
   if v.effect=='heal'then x=p.hp<C.stats(p).hp*.4 and 160 or -1 end
   if v.effect=='sleep' or v.effect=='paralysis'then x=foe.status=='' and 55 or 0 end
   if x>score then score=x;best=i-1 end
  end end
  return best
 end
 function C.turn(p,e,index)
  p.protect=false;e.protect=false;local logs={};local ei=C.ai(e,p)
  local pm=C.move(p.moves[index+1] and p.moves[index+1].name or '挣扎')
  local em=C.move(e.moves[ei+1] and e.moves[ei+1].name or '挣扎')
  local ps=C.speed(p)+(pm.effect=='priority' and 1000 or 0)
  local es=C.speed(e)+(em.effect=='priority' and 1000 or 0)
  local order=ps>=es and {{p,e,index},{e,p,ei}} or {{e,p,ei},{p,e,index}}
  for _,o in ipairs(order)do if o[1].hp>0 and o[2].hp>0 then append(logs,C.attack(o[1],o[2],o[3]))end end
  if p.hp>0 then append(logs,C.endTurn(p))end
  if e.hp>0 then append(logs,C.endTurn(e))end
  return logs
 end
 function C.captureChance(p,ball)
  return math.min(.94,math.max(.03,((3*C.stats(p).hp-2*p.hp)/(3*C.stats(p).hp))
   *(C.spec(p.id).catch/255)*(({ball=1,great=1.5,ultra=2})[ball] or 1)*(p.status~='' and 1.6 or 1)))
 end
 function C.useItem(s,key,p)
  if not s.bag[key] or s.bag[key]==0 then return'道具不足'end
  if key=='revive'then
   if p.hp>0 then return'伙伴没有倒下'end
   s.bag[key]=s.bag[key]-1;p.hp=math.ceil(C.stats(p).hp/2);p.status='';return'伙伴恢复了意识'
  end
  if p.hp<=0 then return'倒下的伙伴需要活力碎片'end
  if key=='cure'then
   if p.status==''then return'没有异常状态'end
   s.bag[key]=s.bag[key]-1;p.status='';return'异常状态已清除'
  end
  if key=='potion' or key=='super'then
   if p.hp==C.stats(p).hp then return'HP 已满'end
   s.bag[key]=s.bag[key]-1;p.hp=math.min(C.stats(p).hp,p.hp+(key=='super' and 80 or 30));return'HP 已恢复'
  end
  return'不能使用'
 end
 function C.clearBattle(p)p.protect=nil;p.accuracy=nil;p.slow=nil end
 return C
end

return {new=make}
end
