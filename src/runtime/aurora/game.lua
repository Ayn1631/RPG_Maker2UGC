-- Aurora.js gameplay port. Source IDs and zero-based campaign indices retained.
-- Views contain callbacks privately; projection exports only immutable UI values.
return function(deps)
 local M={}
 local function copy(v)if type(v)~='table'then return v end;local t={};for k,x in pairs(v)do t[k]=copy(x)end;return t end
 local function has(t,x)for _,v in ipairs(t)do if v==x then return true end end;return false end
 local function append(t,values)for _,v in ipairs(values)do t[#t+1]=v end end
 local function tail(t,n)local r={};for i=math.max(1,#t-n+1),#t do r[#r+1]=t[i]end;return r end
 local items={{'ball','精灵球',120},{'great','超级球',350},{'ultra','高级球',650},{'potion','伤药 +30HP',80},{'super','好伤药 +80HP',220},{'revive','活力碎片',450},{'cure','万能药',120}}
 function M.new(data,host)
  local C=deps['runtime.aurora.core'].new(data,host.random)
  local s=C.state();local A={};local view,battle,fx;local revision,selected,wait=0,0,0
  local function name(p)return C.spec(p.id).name end
  local function alive()for i,p in ipairs(s.party)do if p.hp>0 then return i end end end
  local function choice(label,fn)return{label,fn}end
  local function open(v)view=v;selected=0;revision=revision+1;wait=v.lock and fx and (fx.kind=='ball' and 75 or 38) or 10 end
  function A.back()view=nil;revision=revision+1 end
  function A.say(title,lines,after)
   after=after or A.back;open{title=title,lines=type(lines)=='table' and lines or {lines},onCancel=after,choices={choice('继续',after)}}
  end
  function A.travel(id,x,y,need)
   if id~=2 and #s.party==0 then A.say('旅行提示','先去岚芽镇西北的研究所，领取第一位伙伴吧。');return end
   if need and need>=0 and #s.badges<need then A.say('旅行提示','前方需要 '..need..' 枚徽章。先完成当前城市的道馆试炼吧。');return end
   if id==28 and not s.flags.boss then A.say('旅行提示','蚀星基地仍在抽取归潮塔的力量。先到霜灯市东北阻止夜枢！');return end
   if id==29 and not s.flags.tower then A.say('旅行提示','先到苍穹市东侧的归潮塔，回应洛奇亚的呼唤。');return end
   A.back();host.transfer(id,x,y)
  end
  function A.home()for _,p in ipairs(s.party)do C.heal(p)end;A.say('妈妈',{'累了就回来。宝可梦也需要休息。','HP、异常状态与全部招式 PP 已恢复。'})end
  function A.eevee(p,id)p.id=id;C.heal(p);C.record(s,id,true);p.moves=C.create(id,p.level).moves;A.say('进化','伊布进化成了 '..name(p)..'！')end
  function A.lab()
   if #s.party==0 then
    local cs={};for _,v in ipairs({{1,'妙蛙种子 · 草 / 毒'},{4,'小火龙 · 火'},{7,'杰尼龟 · 水'}})do
     local id=v[1];cs[#cs+1]=choice(v[2],function()C.add(s,C.create(id,8));s.flags.starter=id;A.say('相遇',{'你与'..C.spec(id).name..'成为伙伴！','获得精灵球 ×20、伤药 ×8、图鉴和旅行终端。','向北穿过晨露小径，到青藤市取得第一枚徽章。','Esc 打开终端；中心的同步训练可以减少重复练级。'})end)
    end
    open{title='星榆博士 · 第一位伙伴',lines={'极光正在紊乱。蚀星团企图把变化从世界上抹去。','我想请你带上图鉴，亲眼看看人与宝可梦如何一起生活。','选一位伙伴。选择后不会重置，另外两种能在旅途中捕捉。'},choices=cs,portraits={{id=1},{id=4},{id=7}},tier='detail'};return
   end
   local cs={choice('查看图鉴',function()A.dex()end)}
   for _,p in ipairs(s.party)do if p.id==133 and p.level>=25 then for _,id in ipairs({134,135,136})do cs[#cs+1]=choice('伊布进化为'..C.spec(id).name,function()A.eevee(p,id)end)end;break end end
   cs[#cs+1]=choice('离开',A.back);open{title='星榆研究所',lines={'图鉴会记录所有见过与捕捉过的宝可梦。','本作的石头与通信进化已简化为升级。','伊布满 Lv.25 后，可以在这里选择进化。'},choices=cs}
  end
  function A.center(id)
   s.lastCenter=id;for _,p in ipairs(s.party)do C.heal(p)end
   open{title='宝可梦中心 · 旅途的灯',lines={'队伍已完全恢复，治疗免费。','同步训练可把低等级伙伴提升到当前推荐等级。','电脑仓库最多保存120只；队伍最多6只。'},choices={
    choice('同步训练至 Lv.'..(12+#s.badges*5),function()local logs={};for _,p in ipairs(s.party)do while p.level<12+#s.badges*5 do append(logs,C.exp(p,p.level*12))end;C.heal(p);C.record(s,p.id,true)end;A.say('同步训练完成',#logs>0 and tail(logs,7)or{'伙伴们已经达到当前训练等级。'},function()A.center(id)end)end),
    choice('整理电脑仓库',function()A.storage()end),choice('离开',A.back)}}
  end
  function A.gift(k)
   if s.flags[k]then A.say('旅行补给','这里的补给已经领取过了。');return end
   s.flags[k]=true;s.bag.ball=s.bag.ball+8;s.bag.super=s.bag.super+3;s.bag.revive=s.bag.revive+1;s.money=s.money+600
   A.say('补给已领取',{'精灵球 ×8、好伤药 ×3、活力碎片 ×1、600 元','中心治疗免费；失败会在最近的中心恢复，不丢失伙伴。'})
  end
  function A.shop()
   local cs={};for _,item in ipairs(items)do local k,n,p=table.unpack(item);cs[#cs+1]=choice(n..'  '..p..'元  (持有'..s.bag[k]..')',function()
    if s.money<p then A.say('余额不足','可以挑战道路训练家获得奖金。',A.shop);return end;s.money=s.money-p;s.bag[k]=s.bag[k]+1;A.shop()end)end
   cs[#cs+1]=choice('离开',A.back);open{title='友好商店',lines={'持有 '..s.money..' 元 · 选择道具购买一份'},choices=cs}
  end
  function A.rival(j)
   if #s.party==0 then A.say('阿澈','博士正在等你。快选好伙伴，我们在旅途中再一决胜负。');return end
   A.startBattle{name='劲敌阿澈',key='rival'..j,team={{id=({[1]=4,[4]=7,[7]=1})[s.flags.starter],level=8+j*10},{id=16,level=7+j*10}},reward=500+j*300,win=function()A.say('阿澈',{'我们从同一座小镇出发，却会看到不同的风景。','就这样一路前进吧。下一次，我会变得更强！'})end}
  end
  function A.trainer(k)
   if k=='admin'then A.startBattle{name='蚀星执行官·白烬',key=k,team={{id=94,level=39},{id=42,level=40},{id=65,level=41}},reward=1600,win=function()s.flags.admin=true;A.say('执行官败退','白烬：我以为停止时间就不用再失去……去关闭东侧终端吧。')end};return end
   local j=assert(tonumber(k:match('^route([0-7])$')),'Unknown trainer ID');A.startBattle{name='道路训练家 · '..data.maps[tostring(host.mapId())].name,key=k,
    team={{id=({19,74,54,25,58,92,131,148})[j+1],level=7+j*5},{id=({16,27,129,63,37,41,143,147})[j+1],level=8+j*5}},reward=500+j*180,
    win=function()A.say('训练家',{'打得不错！你可以再次来找我切磋。','中心免费同步训练；尝试不同属性的伙伴会更轻松。'})end}
  end
  function A.villain(j)
   if s.flags['villain'..j]then A.say('蚀星团','电容已经还给城市。我们……也在重新考虑。');return end
   A.startBattle{name='蚀星团 · '..(j==2 and '夺潮小队'or'月镜小队'),team={{id=j==2 and 41 or 93,level=15+j*3},{id=j==2 and 27 or 64,level=16+j*3}},reward=1000,key='villain'..j,
    win=function()s.flags['villain'..j]=true;A.say('被夺走的极光',{'团员：夜枢大人要创造一个永远不再失去的世界。','阿澈：可没有变化，也不会再有相遇。','你夺回了极光电容，城市的灯重新亮了。'})end}
  end
  function A.puzzle(j,k)
   local key='puzzle'..j;local seq=data.puzzles[j+1]
   if s.flags[key]then A.say('机关已开启','三束光连成了前往馆主的道路。');return end
   local p=s.flags[key..'n']or 0
   if k==seq[p+1]then p=p+1;s.flags[key..'n']=p;if p==3 then s.flags[key]=true;A.say('试炼完成','三座机关共鸣！现在可以挑战馆主。')else A.say('正确','机关 '..p..'/3 已点亮。')end
   else s.flags[key..'n']=0;A.say('光芒消散','顺序不对，机关已复位。再读一次中央石碑吧。')end
  end
  function A.gym(j)
   local g=data.gyms[j+1]
   if has(s.badges,j)then A.say(g.name,'你已经获得'..g.badge..'徽章。去迎接下一段旅程吧。');return end
   if #s.badges<j then A.say('道馆挑战顺序','先取得之前城市的徽章，再来挑战。');return end
   if j==7 and not s.flags.tower then A.say('凌岳','北方的天空还没有平静。先解决蚀星基地与归潮塔的事件。');return end
   if not s.flags['puzzle'..j]then A.say('道馆试炼','先完成石碑提示的三机关顺序，再来挑战我。');return end
   A.say(g.name,g.intro,function()A.startBattle{name='馆主 '..g.name,team=g.team,reward=1500+j*400,key='gym'..j,win=function()
    s.badges[#s.badges+1]=j;s.bag.great=s.bag.great+6;s.bag.super=s.bag.super+3;A.say('获得 '..g.badge..'徽章',{g.win,'获得超级球 ×6、好伤药 ×3。','宝可梦中心解锁新的同步训练等级。'})end}end)
  end
  function A.terminal()if not s.flags.admin then A.say('锁定终端','先击败西侧执行官，取得关闭终端的权限。');return end;s.flags.terminal=true;A.say('关闭抽取装置',{'极光电容停止了过载。通往夜枢的防护解除。','阿澈：他不是没有悲伤，只是忘记了世界还会继续。'})end
  function A.boss()
   if s.flags.boss then A.say('夜枢','如果明天仍会有风暴……那就和伙伴一起重建。');return end
   if not s.flags.terminal then A.say('防护装置','先击败执行官并关闭东侧终端。');return end
   A.say('蚀星首领 · 夜枢',{'那场海啸夺走了一切。我不想再让任何人失去家。','洛奇亚能让风暴平息，我要让这一秒永远持续。','如果你相信变化，就用你和伙伴的力量回答我！'},function()
    A.startBattle{name='蚀星首领·夜枢',team={{id=94,level=42},{id=76,level=42},{id=130,level=43},{id=65,level=44}},reward=4000,key='boss',win=function()
     s.flags.boss=true;s.bag.ultra=s.bag.ultra+15;A.say('黎明重新流动',{'机器崩解，银色羽毛朝归潮塔飞去。','夜枢：我只是……不敢再往前走。','你与阿澈一起扶起夜枢，把被囚禁的宝可梦放回天空。','获得高级球 ×15。前往苍穹市东侧的归潮塔。'})end}end)
  end
  function A.towerTalk()A.say('阿澈',{'我们无法保证每天晴朗。','但只要身边还有伙伴，明天就值得期待。','洛奇亚正在塔顶等你。即使不捕捉，战胜它也能推进剧情。'})end
  function A.legend(id)
   if id~=249 and not s.flags.champion then A.say('尚未开启','成为联盟冠军后，新的研究区域才会开放。');return end
   if id==249 and not s.flags.boss then A.say('银色屏障','先阻止蚀星基地的装置。');return end
   if has(s.caught,id)then A.say('曾经的相遇',C.spec(id).name..'已经加入你的队伍或仓库。');return end
   A.say(C.spec(id).name,{'周围的空气仿佛静止了一瞬。','这是野生的相遇。可以捕捉；若击倒或逃走，可以再次挑战。'},function()
    A.startBattle{name='野生 '..C.spec(id).name,wild=true,legend=true,team={{id=id,level=id==249 and 44 or 58}},reward=0,key='legend'..id,win=function()
     if id==249 then s.flags.tower=true;A.say('海与天空的约定',{'洛奇亚认可了你与伙伴之间的羁绊。','海潮恢复了节律，所有城市再次看见极光。','现在可以挑战苍穹道馆，并向联盟前进！'})else A.say('传说仍在延续','你记录了新的相遇。幻之宝可梦的故事还在继续。')end end}end)
  end
  function A.leagueGate()
   if #s.badges<8 then A.say('联盟受付','请取得八枚道馆徽章。');return end
   open{title='星澜联盟 · 参赛登记',lines={'四天王与冠军共五场连续战斗。','开始前与每轮晋级后免费治疗；仍建议携带战斗道具。','中途退赛或全队倒下会重置这一轮进度。'},choices={choice('开始挑战',function()for _,p in ipairs(s.party)do C.heal(p)end;s.league=0;s.flags.leagueActive=true;A.travel(30,14,15)end),choice('再准备一下',A.back)}}
  end
  function A.elite(j)
   if not s.flags.leagueActive or s.league~=j then A.say('联盟赛程','请返回大厅重新登记。');return end
   local e=data.elite[j+1];A.startBattle{name=e.name,team=e.team,key=e.id,reward=2000+j*500,win=function()
    s.league=j+1;if j<4 then for _,p in ipairs(s.party)do C.heal(p)end;s.bag.super=s.bag.super+2 end
    if j==4 then s.flags.champion=true;s.flags.leagueActive=false;A.say('你成为了星澜联盟冠军！',{'星遥：真正强大的训练家，不会独自站在顶点。','冠军殿堂记录下你和六位伙伴的名字。','远处的极光再次亮起，照耀着仍在改变的世界。'},function()A.travel(35,14,15)end)
    else A.say('晋级下一场',{'战胜 '..e.name..'！','医护已恢复全部伙伴与 PP，补充好伤药 ×2。','准备好后，选择下一场。'},function()open{title='联盟休息区',lines={'目前完成 '..(j+1)..'/5 场'},choices={choice('前往下一场',function()A.travel(31+j,14,15)end),choice('整理队伍和道具',A.menu),choice('退赛返回大厅',A.leaveLeague)}}end)end end}
  end
  function A.leaveLeague()open{title='退赛确认',lines={'本轮联盟进度会重置；已获得的徽章与经验保留。'},choices={choice('确认退赛',function()s.league=0;s.flags.leagueActive=false;A.travel(29,14,14)end),choice('继续挑战',A.back)}}end
  function A.ending()A.say('尾声 · 回响不息',{'星榆博士：你记录的不只是宝可梦，也是世界仍在变化的证据。','阿澈：下一次的目标？当然是再和你打一场！','夜枢在澄湾修复灯塔。馆主们回到自己的城市。','而你与伙伴的旅途，才刚刚翻开新的一页。','主线完成。现在可以自由旅行、补全60种图鉴、寻找超梦与梦幻。','感谢游玩《宝可梦：星澜回响》。非商业同人，非官方作品。'})end
  function A.goal()
   if #s.party==0 then return'去岚芽镇西北研究所选择伙伴'end
   if s.flags.champion then return'自由探索 · 补全图鉴与幻之宝可梦研究'end
   if #s.badges<7 then return'前往'..data.cities[#s.badges+2]..'，取得'..data.badges[#s.badges+1]..'徽章'end
   if not s.flags.boss then return'去霜灯市东北蚀星基地，阻止夜枢'end
   if not s.flags.tower then return'去苍穹市东侧归潮塔，回应洛奇亚'end
   if #s.badges<8 then return'挑战苍穹道馆，取得天际徽章'end
   if s.flags.leagueActive then return'联盟挑战：已胜'..s.league..'/5场'end
   return'八枚徽章齐聚，前往苍穹市北方联盟'
  end
  function A.menu()
   local cs={choice('伙伴队伍',function()A.party()end),choice('精灵图鉴  '..#s.caught..'/60',function()A.dex()end),choice('背包与治疗',function()A.bag()end),choice('徽章 / 当前目标',A.journal)}
   if not s.flags.leagueActive and #s.party>0 then cs[#cs+1]=choice('快速旅行',A.fly)end
   if s.flags.leagueActive and s.league>0 and s.league<5 then cs[#cs+1]=choice('前往联盟第 '..(s.league+1)..' 场',function()A.travel(30+s.league,14,15)end)end
   cs[#cs+1]=choice('返回旅途',A.back);open{title='旅行终端',lines={A.goal(),'徽章 '..#s.badges..'/8  ·  见过 '..#s.seen..' / 捕获 '..#s.caught..'  ·  '..s.money..' 元'},choices=cs}
  end
  function A.journal()
   local lines={A.goal()};for i,g in ipairs(data.gyms)do lines[#lines+1]=(has(s.badges,i-1)and'◆'or'◇')..' '..g.badge..'徽章  '..data.cities[i+1]..' · '..g.name end
   lines[#lines+1]=s.flags.boss and'蚀星事件：已解决'or'蚀星事件：等待调查';lines[#lines+1]=s.flags.tower and'归潮塔：已获得认可'or'归潮塔：银色羽毛仍在呼唤'
   open{title='星澜旅行手记',lines=lines,choices={choice('返回终端',A.menu)}}
  end
  function A.fly()
   local cs={};for i=1,math.min(9,#s.badges+2)do local id=data.cityMaps[i];cs[#cs+1]=choice(data.cities[i],function()A.travel(id,15,12)end)end
   if s.flags.champion then cs[#cs+1]=choice('冠军纪念庭',function()A.travel(35,14,15)end)end;cs[#cs+1]=choice('返回',A.menu)
   open{title='城市快线',lines={'只能前往已解锁城市；快速旅行免费。'},choices=cs}
  end
  function A.party(inBattle)
   local cs={};for i,p in ipairs(s.party)do cs[#cs+1]=choice(i..'. '..name(p)..' Lv.'..p.level..'   HP '..p.hp..'/'..C.stats(p).hp..' '..p.status,function()if inBattle then A.switchTo(i)else A.detail(i)end end)end
   cs[#cs+1]=choice('返回',inBattle and A.battleMenu or A.menu);open{title=inBattle and'选择换上的伙伴'or'伙伴队伍 · 点击伙伴查看详情',lines={inBattle and'换人会消耗本回合；倒下后强制换人不消耗回合。'or'队首是野外战斗的默认出场伙伴。'},choices=cs,portraits=s.party,tier='portrait'}
  end
  function A.detail(i)
   local p=s.party[i];local sp,st=C.spec(p.id),C.stats(p);local lines={table.concat(sp.types,' / ')..'    HP '..p.hp..'/'..st.hp..'    '..(p.status~=''and p.status or'状态良好'),'攻击 '..st.atk..'  防御 '..st.def..'  速度 '..st.spd,'经验 '..p.xp..'/'..p.level*12}
   for _,m in ipairs(p.moves)do local def=C.move(m.name);lines[#lines+1]=m.name..' ['..def.type..'] 威力'..def.power..'  PP '..m.pp..'/'..def.pp end
   lines[#lines+1]=sp.evolve and sp.evolve~=0 and 'Lv.'..sp.evolveLevel..' 可进化'or'已达到本形态进化终点'
   open{title=name(p)..' · Lv.'..p.level,lines=lines,portraits={p},tier='detail',choices={choice('设为队首',function()table.remove(s.party,i);table.insert(s.party,1,p);A.party()end),choice('返回队伍',function()A.party()end)}}
  end
  function A.storage(page)
   page=page or 0;local cs={choice('存入一位伙伴',function()
    local choices={};for i,p in ipairs(s.party)do choices[#choices+1]=choice(name(p)..' Lv.'..p.level,function()
     if #s.box>=120 then A.say('仓库已满','仓库最多120只，请先调整队伍。',A.storage);return end
     local other=false;for j,q in ipairs(s.party)do if j~=i and q.hp>0 then other=true end end
     if #s.party<=1 or not other then A.say('无法存入','需要留下一位能战斗的伙伴。',A.storage);return end
     s.box[#s.box+1]=table.remove(s.party,i);A.storage()end)end;choices[#choices+1]=choice('返回',A.storage);open{title='存入伙伴',lines={'至少保留一位能战斗的伙伴'},choices=choices,portraits=s.party,tier='portrait'}end)}
   local portraits={};for i=page*6+1,math.min(#s.box,page*6+6)do local p=s.box[i];portraits[#portraits+1]=p;cs[#cs+1]=choice(i..'. 取出 '..name(p)..' Lv.'..p.level,function()
    if #s.party>=6 then A.say('队伍已满','先存入一位伙伴。',function()A.storage(page)end);return end;s.party[#s.party+1]=table.remove(s.box,i);A.storage(page)end)end
   if page>0 then cs[#cs+1]=choice('上一页',function()A.storage(page-1)end)end;if (page+1)*6<#s.box then cs[#cs+1]=choice('下一页',function()A.storage(page+1)end)end
   cs[#cs+1]=choice('放生仓库伙伴（腾出空间）',function()A.release(page)end);cs[#cs+1]=choice('返回中心',function()A.center(s.lastCenter)end)
   open{title='电脑仓库 '..#s.box..'/120',lines={'存入保留至少一位能战斗的伙伴。取出需要队伍空位。'},choices=cs,portraits=portraits,tier='portrait'}
  end
  function A.release(page)
   page=page or 0;local cs={};for i=page*6+1,math.min(#s.box,page*6+6)do local p=s.box[i];cs[#cs+1]=choice(name(p)..' Lv.'..p.level,function()
    open{title='确认放生 '..name(p)..'？',lines={'这一只伙伴将从当前冒险中移除。'},choices={choice('确认放生',function()table.remove(s.box,i);A.storage(page)end),choice('取消',function()A.storage(page)end)}}end)end
   cs[#cs+1]=choice('返回仓库',function()A.storage(page)end);open{title='放生仓库伙伴',lines={'图鉴记录会保留，但被放生的这一只将离开。','请慎重选择；队伍中的伙伴不能在这里放生。'},choices=cs}
  end
  function A.bag(inBattle)
   local cs={};for _,item in ipairs(items)do local k,n=item[1],item[2];cs[#cs+1]=choice(n..' ×'..s.bag[k],function()
    if k=='ball'or k=='great'or k=='ultra'then if inBattle then A.throwBall(k)else A.say('精灵球','进入野生战斗后，在背包中投球。',A.bag)end;return end
    local choices={};for _,p in ipairs(s.party)do choices[#choices+1]=choice(name(p)..' '..p.hp..'/'..C.stats(p).hp..' '..p.status,function()
     local before=s.bag[k];local msg=C.useItem(s,k,p);if inBattle and s.bag[k]<before then A.enemyTurn({msg})else A.say(n,msg,function()A.bag(inBattle)end)end end)end
    choices[#choices+1]=choice('返回',function()A.bag(inBattle)end);open{title=n..' · 选择伙伴',lines={},choices=choices,portraits=s.party,tier='portrait'}end)end
   cs[#cs+1]=choice('返回',inBattle and A.battleMenu or A.menu);open{title='背包',lines={inBattle and'使用恢复道具消耗一回合；精灵球仅能在野生战斗使用。'or'选择道具，再选择伙伴。'},choices=cs}
  end
  function A.dex(page)
   page=page or 0;local cs={};for i=page*7+1,math.min(#data.speciesIds,page*7+7)do local id=data.speciesIds[i];cs[#cs+1]=choice((has(s.caught,id)and'●'or has(s.seen,id)and'○'or'?')..string.format(' #%03d ',id)..(has(s.seen,id)and C.spec(id).name or'未发现'),function()A.dexEntry(id,page)end)end
   if page>0 then cs[#cs+1]=choice('上一页',function()A.dex(page-1)end)end;if (page+1)*7<#data.speciesIds then cs[#cs+1]=choice('下一页',function()A.dex(page+1)end)end
   cs[#cs+1]=choice('返回终端',A.menu);open{title='宝可梦图鉴 '..#s.caught..'/60',lines={'见过 '..#s.seen..' 种  ·  第 '..(page+1)..'/'..math.ceil(#data.speciesIds/7)..' 页'},choices=cs}
  end
  function A.dexEntry(id,page)
   local sp=C.spec(id);local seen=has(s.seen,id);local loc=data.locations[tostring(id)]
   open{title=string.format('#%03d ',id)..(seen and sp.name or'未发现'),lines=seen and {table.concat(sp.types,' / '),has(s.caught,id)and sp.desc or'尚未捕获，生态描述待补全。','分布：'..loc,sp.evolve and sp.evolve~=0 and'进化：Lv.'..sp.evolveLevel..' → '..C.spec(sp.evolve).name or'进化：最终形态',has(s.caught,id)and'捕获记录：已登记'or'捕获记录：未捕获'}or{'继续探索星澜地区，与更多宝可梦相遇。'},choices={choice('返回图鉴',function()A.dex(page)end)},portraits=seen and{{id=id}}or{},tier='detail'}
  end
  function A.enemy()return battle.enemies[math.min(battle.ei,#battle.enemies)]end
  function A.player()return s.party[battle.pi]end
  function A.startBattle(spec)
   fx=nil;if #s.party==0 then A.say('尚无伙伴','先去研究所领取伙伴。');return end
   if not alive()then for _,p in ipairs(s.party)do C.heal(p)end;A.say('队伍需要休息','伙伴已恢复，请重新发起挑战。');return end
   if host.audio then host.audio.command{channel='bgm',action='save'};host.audio.command{channel='bgm',action='play',cue=data.battleCue}end
   battle={};for k,v in pairs(spec)do battle[k]=v end;battle.enemies={};for _,p in ipairs(spec.team)do battle.enemies[#battle.enemies+1]=C.create(p.id,p.level)end
   battle.pi,battle.ei=alive(),1;battle.finished,battle.forced=false,false;for _,p in ipairs(s.party)do C.clearBattle(p)end;for _,p in ipairs(battle.enemies)do C.clearBattle(p)end
   C.record(s,A.enemy().id,false);A.log({spec.wild and'野生的 '..name(A.enemy())..' 出现了！'or spec.name..' 发起了挑战！'},A.battleMenu)
  end
  function A.battleMenu()
   if not battle or battle.finished then return end;battle.displayEnemy=nil
   open{title=battle.name,battle=true,lines={'轮到你行动。属性克制与 PP 会影响战局。'},choices={choice('战斗 · 选择招式',A.moves),choice('背包 · 道具 / 捕捉',function()A.bag(true)end),choice('宝可梦 · 换人',function()A.party(true)end),choice('逃跑',function()if not battle.wild then A.log({'训练家战斗不能逃跑。'},A.battleMenu)else A.finish('run')end end)}}
  end
  function A.moves()
   local p=A.player();local cs,valid={},false
   for i,m in ipairs(p.moves)do local def=C.move(m.name);if m.pp>0 then valid=true end;cs[#cs+1]=choice(m.name..' ['..def.type..']  威力'..def.power..'  PP '..m.pp..'/'..def.pp,function()
    if m.pp<=0 then A.log({'这个招式的 PP 用尽了。'},A.moves);return end;A.animate('attack');A.resolve(C.turn(p,A.enemy(),i-1))end)end
   if not valid then cs[#cs+1]=choice('挣扎（会受到反伤）',function()A.animate('attack');A.resolve(C.turn(p,A.enemy(),-1))end)end
   cs[#cs+1]=choice('返回',A.battleMenu);open{title='选择招式',battle=true,lines={'同属性招式获得 1.5 倍加成。'},choices=cs}
  end
  function A.log(logs,after)
   local lines={};for i=1,math.min(8,#logs)do lines[#lines+1]=logs[i]end
   open{title=battle and battle.name or'旅途记录',lock=true,battle=battle~=nil,lines=lines,choices={choice('继续',function()if #logs>8 then local rest={};for i=9,#logs do rest[#rest+1]=logs[i]end;A.log(rest,after)else after()end end)}}
  end
  function A.resolve(logs)
   local b,p,e=battle,A.player(),A.enemy()
   if not alive()then logs[#logs+1]='所有伙伴都倒下了。';A.log(logs,function()A.finish('lose')end);return end
   if e.hp<=0 then
    b.displayEnemy=e;logs[#logs+1]=name(e)..' 倒下了！';local gain=e.level*(b.wild and 8 or 13)
    for _,q in ipairs(s.party)do if q.hp>0 then append(logs,C.exp(q,gain));C.record(s,q.id,true)end end
    b.ei=b.ei+1;if b.ei>#b.enemies then A.log(logs,function()A.finish('win')end);return end
    C.record(s,A.enemy().id,false);logs[#logs+1]=b.name..' 派出了 '..name(A.enemy())
   end
   if p.hp<=0 then logs[#logs+1]=name(p)..' 倒下了！';b.forced=true;A.log(logs,A.forceSwitch);return end
   A.log(logs,A.battleMenu)
  end
  function A.forceSwitch()
   local cs={};for i,p in ipairs(s.party)do cs[#cs+1]=choice(name(p)..'  HP '..p.hp..'/'..C.stats(p).hp,function()if p.hp<=0 then A.forceSwitch();return end;battle.pi=i;battle.forced=false;A.battleMenu()end)end
   open{title='请选择下一位伙伴',lock=true,battle=true,lines={'换人不会消耗回合。'},choices=cs}
  end
  function A.switchTo(i)
   local p=s.party[i];if p.hp<=0 then A.log({'这个伙伴已经倒下。'},function()A.party(true)end);return end
   if i==battle.pi then A.log({'已经在场上。'},function()A.party(true)end);return end
   battle.pi=i;C.clearBattle(p);if battle.forced then battle.forced=false;A.battleMenu()else A.enemyTurn({'去吧，'..name(p)..'！'})end
  end
  function A.enemyTurn(logs)
   if not fx or fx.kind~='ball'or fx.t>0 then A.animate('attack')end
   local p,e=A.player(),A.enemy();e.protect,p.protect=false,false;append(logs,C.attack(e,p,C.ai(e,p)));append(logs,C.endTurn(p));append(logs,C.endTurn(e));A.resolve(logs)
  end
  function A.throwBall(key)
   local b,e=battle,A.enemy()
   if not b.wild then A.log({'不能捕捉其他训练家的宝可梦。道具未消耗。'},function()A.bag(true)end);return end
   if s.bag[key]==0 then A.log({'没有这种精灵球了。'},function()A.bag(true)end);return end
   if #s.party>=6 and #s.box>=120 then A.log({'队伍和电脑仓库都已满。先整理空间。道具未消耗。'},function()A.bag(true)end);return end
   A.animate('ball');s.bag[key]=s.bag[key]-1
   if C.rng()<C.captureChance(e,key)then fx.success=true;C.clearBattle(e);C.add(s,e);A.log({'精灵球晃动了三次……成功捕获 '..name(e)..'！',has(s.party,e)and'伙伴已加入队伍。'or'伙伴已送入电脑仓库。'},function()A.finish('caught')end)
   else A.enemyTurn({'精灵球晃动……对方挣脱了！'})end
  end
  function A.finish(result)
   local b=battle;if not b or b.finished then return end;b.finished=true;for _,p in ipairs(s.party)do C.clearBattle(p)end;battle,fx=nil,nil
   if host.audio then host.audio.command{channel='bgm',action='replay'}end
   if result=='lose'then s.money=math.max(0,s.money-math.min(300,math.floor(s.money*.1)));for _,p in ipairs(s.party)do C.heal(p)end;s.flags.leagueActive=false;s.league=0
    A.say('暂时休整',{'全队倒下，但没有伙伴离开。','中心已为队伍恢复。损失少量旅费，可以重新挑战。'},function()A.back();host.transfer(s.lastCenter,15,12)end);return end
   if result=='run'then A.say('安全离开','你和伙伴离开了这场野生战斗。');return end
   s.money=s.money+(b.reward or 0);if b.win then b.win();return end
   A.say(result=='caught'and'新的伙伴'or'战斗胜利',result=='caught'and'图鉴已更新。'or'获得 '..(b.reward or 0)..' 元。伙伴们累积了新的经验。')
  end
  function A.animate(kind)fx={kind=kind,t=0,pid=A.player().id,eid=A.enemy().id,php=A.player().hp,ehp=A.enemy().hp}end
  local function terrain()local m=data.maps[tostring(host.mapId())];if m.kind=='legend'or m.kind=='postgame'then return'Temple'end;if m.kind=='gym'or m.kind=='arena'or m.kind=='league'then return'Gym'end;if m.kind=='hq'or m.route==1 then return'Cave'end;if m.route==2 then return'Sea'end;if m.route==6 or m.city==7 then return'Snow'end;return'Grass'end
  local api={}
  function api.invoke(method,args)assert(type(A[method])=='function','Uncompiled Aurora command');A[method](table.unpack(args or{}))end
  function api.active()return view~=nil end
  function api.menu()A.menu()end
  function api.tick(frames)wait=math.max(0,wait-frames);if fx and fx.t<75 then fx.t=math.min(75,fx.t+frames)end end
  function api.step(region,busy)
   s.steps=s.steps+1
   if #s.party>0 and region==1 and s.steps-(s.lastEncounter or 0)>6 and C.rng()<.16 and not busy then
    local m=data.maps[tostring(host.mapId())];if m and m.pool then s.lastEncounter=s.steps;local id=m.pool[1+math.floor(C.rng()*#m.pool)];local level=m.level+math.floor(C.rng()*4);A.startBattle{name='野生 '..C.spec(id).name,wild=true,team={{id=id,level=level}},reward=0}end
   end
  end
  function api.input(kind,value)
   if not view or wait>0 then return false end
   local n=#view.choices
   if kind=='navigate'then if n==0 or value~=2 and value~=8 then return false end;selected=(selected+(value==2 and 1 or -1)+n)%n;return true end
   if kind=='cancel'or kind=='menu'then if view.lock then return false end;if view.onCancel then view.onCancel()elseif battle then if battle.forced then return false end;A.battleMenu()else A.back()end;return true end
   if kind=='touch'then if type(value)~='number'or value%1~=0 or value<0 or value>=n then return false end;selected=value end
   if kind=='touch'or kind=='confirm'then local row=view.choices[selected+1];if not row then return false end;wait=12;row[2]();return true end
   return false
  end
  function api.view()
   if not view then return nil end
   local out={title=view.title,lines=copy(view.lines or{}),choices={},selectedIndex=selected,revision=revision,portraits={},tier=view.tier or'portrait',lock=view.lock==true,waiting=wait>0}
   for _,r in ipairs(view.choices)do out.choices[#out.choices+1]=r[1]end
   for _,p in ipairs(view.portraits or{})do out.portraits[#out.portraits+1]={id=p.id}end
   if view.battle and battle then
    local function battler(p)return{id=p.id,name=name(p),level=p.level,hp=p.hp,maxHp=C.stats(p).hp,status=p.status,types=table.concat(C.spec(p.id).types,'/')}end
    out.battle={player=battler(A.player()),enemy=battler(battle.displayEnemy or A.enemy()),terrain=terrain(),fx=copy(fx)}
   end
   return out
  end
  function api.hud()return A.goal()end
  function api.snapshot()return copy(s)end
  return api
 end
 return M
end
