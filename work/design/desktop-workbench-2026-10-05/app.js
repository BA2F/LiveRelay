'use strict';

(() => {
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const esc = value => String(value ?? '').replace(/[&<>"']/g, character => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[character]));
  const clone = value => JSON.parse(JSON.stringify(value));
  const icons = {
    grid:'<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
    chat:'<path d="M21 11.5a8.4 8.4 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.4 8.4 0 0 1-3.8-.9L3 21l1.9-5.7a8.4 8.4 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.4 8.4 0 0 1 3.8-.9h.5a8.5 8.5 0 0 1 8 8v.5z"/>',
    graph:'<circle cx="5" cy="6" r="3"/><circle cx="19" cy="6" r="3"/><circle cx="12" cy="19" r="3"/><path d="m7 8 3.5 8m6.5-8-3.5 8M8 6h8"/>',
    history:'<path d="M3 11a9 9 0 1 1 2.7 7M3 4v7h7m2-4v5l3 2"/>',
    folder:'<path d="M3 7V5a2 2 0 0 1 2-2h4l2 3h8a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z"/>',
    file:'<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8zM14 2v6h6M8 13h8m-8 4h6"/>',
    image:'<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8" cy="8" r="1.5"/><path d="m21 15-5-5L5 21"/>',
    audio:'<path d="M9 18V5l12-2v13M9 8l12-2"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>',
    video:'<rect x="2" y="5" width="14" height="14" rx="2"/><path d="m16 10 6-4v12l-6-4z"/>',
    settings:'<path d="m9 3 1-1h4l1 1 .5 3 2.5 1 3-.5 2 3-2 2v3l2 2-2 3-3-.5-2.5 1-.5 3-1 1h-4l-1-1-.5-3-2.5-1-3 .5-2-3 2-2v-3l-2-2 2-3 3 .5 2.5-1z"/><circle cx="12" cy="12" r="3"/>',
    lock:'<rect x="4" y="10" width="16" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',
    sun:'<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5"/>',
    moon:'<path d="M21 12.8A9 9 0 1 1 11.2 3 7 7 0 0 0 21 12.8z"/>',
    close:'<path d="m6 6 12 12M6 18 18 6"/>',
    plus:'<path d="M12 5v14M5 12h14"/>',
    search:'<circle cx="10.5" cy="10.5" r="7"/><path d="m16 16 5 5"/>',
    chevron:'<path d="m8 10 4 4 4-4"/>',
    panel:'<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M15 3v18"/>',
    split:'<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M12 3v18"/>',
    external:'<path d="M15 3h6v6m0-6-10 10M9 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-4"/>',
    mic:'<rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2m-7 9v3m-4 0h8"/>',
    send:'<path d="m5 12 7-7 7 7m-7-7v14"/>',
    clip:'<path d="m21 11-8 8a6 6 0 0 1-8.5-8.5L13 2a4 4 0 0 1 5.7 5.7l-9 9a2 2 0 0 1-2.8-2.8l8-8"/>',
    eye:'<path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
    edit:'<path d="m16 3 5 5-12 12-6 1 1-6zM14 5l5 5"/>',
    check:'<path d="m5 12 4 4L19 6"/>',
    book:'<path d="M12 5c-4-3-8-2-10-1v15c3-1 6-2 10 1 4-3 7-2 10-1V4c-2-1-6-2-10 1zM12 5v15"/>'
  };
  const icon = name => `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${icons[name] || icons.file}</svg>`;
  const storageKey = 'liverelay-workbench-demo-v1'+(new URLSearchParams(location.search).has('qa')?'-qa':'');
  const initialSources = [
    {id:'property-text',type:'text',name:'房产资料存放记录.txt',time:'2026-10-05 09:12',description:'本人输入 · 虚构原始文字',url:'assets/property-source.txt',text:'今天把家里的房产资料归拢了一下。\n\n房产证和购房合同放在卧室衣柜最上面一层，靠右的红色文件袋里。文件袋上贴了“房屋资料”标签。\n\n电子扫描件还没有整理。等整理好之后，应该和这条记录关联起来。\n\n这是一段用于界面演示的虚构资料。'},
    {id:'property-image',type:'image',name:'文件袋位置示意.svg',time:'2026-10-05 09:15',description:'位置示意图 · 非真实照片',url:'assets/location.svg'},
    {id:'family-audio',type:'audio',name:'家庭资料录音示例.wav',time:'2026-10-05 09:18',description:'合成提示音 · 用于演示音频播放',url:'assets/sample-audio.wav'},
    {id:'family-video',type:'video',name:'资料位置演示.webm',time:'2026-10-05 09:20',description:'合成视频 · 用于演示录像播放',url:'assets/sample-video.webm'},
    {id:'network-text',type:'text',name:'家庭网络维护记录.txt',time:'2026-10-04 20:32',description:'本人输入 · 虚构原始文字',url:'assets/network-source.txt',text:'家庭网络维护记录\n\n路由器在客厅电视柜后面。断网时先检查光猫，再重启路由器，重启后等待两分钟。\n\n运营商合同和设备购买记录应分别留存。这里没有录入账号或密码。\n\n此内容仅供界面演示。'},
    {id:'medical-text',type:'text',name:'重要联系人原始记录.txt',time:'2026-10-04 18:10',description:'本人输入 · 虚构原始文字',url:'assets/contact-source.txt',text:'重要联系人资料需要定期核对。\n\n先保存联系人的角色、可以提供什么帮助，以及上次核对时间。联系方式暂时没有填写。\n\n本例没有真实姓名和联系方式。'}
  ];
  const initialCards = [
    {id:'property',title:'房产资料在哪里',summary:'房产证和购房合同放在卧室衣柜上层，靠右的红色文件袋中。\n文件袋贴有“房屋资料”标签，电子扫描件待补充。',box:'家庭',tags:['居住','重要资料'],status:'已确认',revision:3,sources:['property-text','property-image'],policy:'仅本人',updated:'今天 09:24'},
    {id:'network',title:'家庭网络维护',summary:'路由器位于客厅电视柜后。\n断网时先检查光猫，再重启路由器并等待两分钟。账号与密码单独管理。',box:'家庭',tags:['网络','设备'],status:'已确认',revision:2,sources:['network-text'],policy:'仅本人',updated:'昨天 20:40'},
    {id:'family',title:'一次家庭资料整理',summary:'保留这次整理的录音与位置演示。\n下一步核对纸质资料，补充对应卡片和电子原件。',box:'家庭',tags:['整理记录'],status:'待确认',revision:1,sources:['family-audio','family-video'],policy:'仅本人',updated:'今天 09:20'},
    {id:'contacts',title:'重要联系人清单',summary:'记录各位联系人的角色、可以提供的帮助和核对时间。\n联系方式待本人补充。',box:'个人',tags:['联系人'],status:'待确认',revision:1,sources:['medical-text'],policy:'仅本人',updated:'昨天 18:10'}
  ];
  const initialHistory = [
    {id:'change-property',title:'核对房产资料存放位置',actor:'本人修改',time:'今天 09:24',changes:[{cardId:'property',title:'房产资料在哪里',before:'房产资料放在书房的文件柜中。位置有待核对。',after:initialCards[0].summary,beforeRevision:2,afterRevision:3,notes:'内容更新 · 收纳在家庭盒子 · 可见范围保持仅本人'}]},
    {id:'change-network',title:'补充网络维护步骤',actor:'本人修改',time:'昨天 20:40',changes:[{cardId:'network',title:'家庭网络维护',before:'路由器位于客厅电视柜后。',after:initialCards[1].summary,beforeRevision:1,afterRevision:2,notes:'补充两步排查顺序'}]},
    {id:'change-family',title:'收纳家庭整理原件',actor:'本人记录',time:'今天 09:20',changes:[{cardId:'family',title:'一次家庭资料整理',before:'',after:initialCards[2].summary,beforeRevision:0,afterRevision:1,notes:'新建卡片 · 关联录音与录像 · 待本人确认'}]}
  ];
  const initialProviders = [
    {id:'deepseek',name:'DeepSeek',endpoint:'https://api.deepseek.com/responses',protocol:'Responses',models:['deepseek-flash'],connected:true},
    {id:'openai',name:'OpenAI',endpoint:'https://api.openai.com/v1/responses',protocol:'Responses',models:['自定义模型'],connected:true},
    {id:'custom',name:'自定义服务',endpoint:'https://example.invalid/v1',protocol:'兼容 API',models:['示例模型'],connected:false}
  ];
  const defaultGroups = mode => mode === 'assistant' ? [{tabs:['agent','cards','changes'],active:'agent'},{tabs:['card:property','graph','sources'],active:'card:property'}] : [{tabs:['cards','card:property','graph','changes'],active:'cards'}];
  const defaults = {version:1,theme:'dark',home:null,mode:'library',dock:'right',groups:defaultGroups('library'),providers:clone(initialProviders),model:{providerId:'deepseek',name:'deepseek-flash'},speech:'local',cards:clone(initialCards),history:clone(initialHistory),navigatorHidden:false};
  let saved;
  try { saved = JSON.parse(localStorage.getItem(storageKey)); } catch {}
  let state = saved?.version === 1 ? {...clone(defaults),...saved} : clone(defaults);
  let sources = clone(initialSources);
  let focusedGroup = 0, currentCardId = 'property', currentFilter = '全部', searchQuery = '', selectedOperation = state.history[0]?.id, selectedChange = 0, diffUnified = false;
  let messages = [], contexts = [], previews = new Set(), voiceTimer, voiceStart, voiceActive = false, sendTimer, toastTimer;
  let dragTab = null, suppressGraphClick = false;
  const params = new URLSearchParams(location.search);
  const popout = params.get('popout');
  const agent = $('#agentPane');
  const groupRoot = $('#editorGroups');
  const cardById = id => state.cards.find(card => card.id === id);
  const sourceById = id => sources.find(source => source.id === id);
  const sourceIcon = source => ({text:'file',image:'image',audio:'audio',video:'video'}[source?.type] || 'file');
  state.cards.forEach(card=>{if(card.agentSource&&!sourceById(card.agentSource.id))sources.push(card.agentSource);});

  function persist() {
    const snapshot = {...state,cards:state.cards.filter(card=>!card.ephemeral).map(card=>({...card,sources:card.sources.filter(id=>!sourceById(id)?.ephemeral)})),history:state.history.filter(op=>!op.ephemeral)};
    if (popout && saved) Object.assign(snapshot,{groups:saved.groups,dock:saved.dock,mode:saved.mode,navigatorHidden:saved.navigatorHidden});
    try { localStorage.setItem(storageKey,JSON.stringify(snapshot)); } catch { toast('浏览器存储不可用；本次修改仍可继续演示'); }
  }
  function toast(text) { clearTimeout(toastTimer); $('#toast').textContent=text; $('#toast').classList.add('visible'); $('#statusInfo').textContent=text; toastTimer=setTimeout(()=>$('#toast').classList.remove('visible'),3500); }
  function applyTheme() { document.documentElement.dataset.theme=state.theme; $('#themeButton').innerHTML=icon(state.theme==='dark'?'sun':'moon'); }
  function tabInfo(tab) {
    if(tab.startsWith('card:'))return {title:cardById(tab.slice(5))?.title||'卡片',icon:'file'};
    if(tab.startsWith('source:'))return {title:sourceById(tab.slice(7))?.name||'原始资料',icon:sourceIcon(sourceById(tab.slice(7)))};
    return {cards:{title:'资料工作台',icon:'grid'},agent:{title:'助手会话',icon:'chat'},graph:{title:'资料关系',icon:'graph'},changes:{title:'变更',icon:'history'},sources:{title:'原始资料',icon:'folder'}}[tab]||{title:'视图',icon:'file'};
  }
  function validTab(tab) { return !tab.startsWith('card:')&&!tab.startsWith('source:') || tab.startsWith('card:')&&!!cardById(tab.slice(5)) || tab.startsWith('source:')&&!!sourceById(tab.slice(7)); }
  state.groups=state.groups.map(group=>({tabs:group.tabs.filter(validTab),active:validTab(group.active)?group.active:'cards'}));
  if(!state.groups.length)state.groups=defaultGroups('library');
  function renderNavigation() {
    $('#navigatorContent').innerHTML=`<div class="nav-section"><div class="section-label">工作区</div>${[['cards','grid','全部卡片',state.cards.length],['cards-draft','file','待确认',state.cards.filter(c=>c.status==='待确认').length],['sources','folder','原始资料',sources.length],['changes','history','最近变更','']].map(([tab,ico,label,count])=>`<button class="tree-item ${tab==='cards'&&currentFilter==='全部'?'active':''}" data-action="nav" data-tab="${tab}">${icon(ico)}<span>${label}</span><small>${count}</small></button>`).join('')}</div><div class="nav-section"><div class="section-label">收纳盒子</div>${['家庭','个人',...new Set(state.cards.map(c=>c.box).filter(b=>!['家庭','个人'].includes(b)))].map(box=>`<button class="tree-item ${currentFilter===box?'active':''}" data-action="filter" data-filter="${esc(box)}">${icon('folder')}<span>${esc(box)}</span><small>${state.cards.filter(c=>c.box===box).length}</small></button>${state.cards.filter(c=>c.box===box).map(c=>`<button class="tree-item child" draggable="true" data-card-drag="${esc(c.id)}" data-action="open-card" data-id="${esc(c.id)}">${icon('file')}<span>${esc(c.title)}</span></button>`).join('')}`).join('')}</div><div class="nav-section"><div class="section-label">快捷视图</div><button class="tree-item" data-action="nav" data-tab="graph">${icon('graph')}<span>资料关系图</span></button><button class="tree-item" data-action="show-agent">${icon('chat')}<span>打开助手</span></button></div>`;
    $('#shell').classList.toggle('navigator-hidden',state.navigatorHidden);
  }
  function renderCard(card,detail=false) {
    return `<article class="info-card" draggable="true" data-card-drag="${esc(card.id)}"><div class="card-top"><span class="card-type">${esc(card.box)}</span><span>· ${esc(card.status)}</span><button class="icon-button card-menu" data-action="edit-card" data-id="${esc(card.id)}" aria-label="编辑${esc(card.title)}">${icon('edit')}</button></div><h2 class="card-title"><button class="title-link" data-action="open-card" data-id="${esc(card.id)}">${esc(card.title)}</button></h2><p class="card-summary">${esc(card.summary)}</p><div class="card-tags">${card.tags.map(tag=>`<span class="tag">${esc(tag)}</span>`).join('')}<span class="tag">${esc(card.policy)}</span></div><div class="sources-area"><div class="sources-caption">${icon('clip')}<span>原始资料 · ${card.sources.length}</span></div>${card.sources.map(id=>{const source=sourceById(id);if(!source)return '';const expanded=previews.has(`${card.id}:${id}`);return `<div class="source-row"><button class="source-link" data-action="preview" data-card="${esc(card.id)}" data-source="${esc(id)}" aria-expanded="${expanded}">${icon(sourceIcon(source))}<span class="source-name">${esc(source.name)}</span>${icon('chevron')}</button><button class="icon-button" data-action="open-source" data-id="${esc(id)}" aria-label="在新标签打开${esc(source.name)}">${icon('external')}</button></div>${expanded?`<div class="inline-preview">${renderMedia(source)}<div class="preview-toolbar"><span>${esc(source.description)}</span><button data-action="open-source" data-id="${esc(id)}">打开原始资料</button></div></div>`:''}`;}).join('')}${detail?`<div class="source-note">第 ${card.revision} 版 · 更新于 ${esc(card.updated)}</div>`:''}</div></article>`;
  }
  function renderMedia(source) {
    if(source.type==='text')return `<div class="original-paper">${esc(source.text)}</div>`;
    if(source.type==='image')return `<img src="${esc(source.url)}" alt="${esc(source.name)}">`;
    if(source.type==='audio')return `<audio controls preload="metadata" src="${esc(source.url)}" aria-label="${esc(source.name)}"></audio>`;
    return `<video controls preload="metadata" playsinline src="${esc(source.url)}" aria-label="${esc(source.name)}"></video>`;
  }
  function renderCatalog() {
    const cards=state.cards.filter(card=>(currentFilter==='全部'||currentFilter==='待确认'&&card.status==='待确认'||card.box===currentFilter)&&`${card.title} ${card.summary} ${card.tags.join(' ')}`.toLowerCase().includes(searchQuery.toLowerCase()));
    return `<div class="view-header"><div><h1>${currentFilter==='全部'?'资料工作台':esc(currentFilter)}</h1><p>${cards.length} 张卡片 · 标题、总结与原始资料</p></div><div class="actions"><button class="button" data-action="new-card">${icon('plus')}新建卡片</button></div></div><div class="filterbar">${['全部','家庭','个人','待确认'].map(filter=>`<button class="filter-button ${filter===currentFilter?'active':''}" data-action="filter" data-filter="${filter}">${filter}</button>`).join('')}</div>${cards.length?`<div class="cards-grid">${cards.map(card=>renderCard(card)).join('')}</div>`:`<div class="empty-view"><h2>没有找到对应卡片</h2><span>试试其他关键词或分类</span></div>`}`;
  }
  function renderDetail(id) {
    const card=cardById(id);if(!card)return '<div class="empty-view">这张卡片已不在示例资料中</div>';
    return `<div class="card-detail">${renderCard(card,true)}<div class="detail-context"><button class="button" data-action="reference" data-id="${esc(id)}">${icon('chat')}交给助手</button><button class="button" data-action="card-history" data-id="${esc(id)}">${icon('history')}修订历史</button><button class="button" data-action="card-graph" data-id="${esc(id)}">${icon('graph')}关联资料</button><button class="button" data-action="import">${icon('clip')}添加原始资料</button>${card.status==='待确认'?`<button class="button primary" data-action="confirm-card" data-id="${esc(id)}">${icon('check')}本人确认</button>`:''}</div></div>`;
  }
  function renderSource(id) {
    const source=sourceById(id);if(!source)return '<div class="empty-view">此临时文件需重新选择</div>';
    const related=state.cards.filter(card=>card.sources.includes(id));
    return `<div class="view-header"><div><h1>${esc(source.name)}</h1><p>${esc(source.description)} · ${esc(source.time)}</p></div><div class="actions">${source.url?`<a class="button" href="${esc(source.url)}" target="_blank" rel="noopener">${icon('external')}打开文件</a>`:''}<button class="button" data-action="popout-source" data-id="${esc(id)}">${icon('external')}独立窗口</button></div></div><div class="source-view">${renderMedia(source)}<div class="source-note">关联卡片：${related.map(card=>`<button class="button ghost" data-action="open-card" data-id="${esc(card.id)}">${esc(card.title)}</button>`).join(' ')||'尚未关联'}</div></div>`;
  }
  function renderSources() { return `<div class="view-header"><div><h1>原始资料</h1><p>原文、图片、录音与录像</p></div><button class="button" data-action="import">${icon('plus')}添加资料</button></div><div class="source-list">${sources.map(source=>`<div class="source-list-item">${icon(sourceIcon(source))}<div class="source-meta"><strong>${esc(source.name)}</strong><p>${esc(source.description)}</p></div><button class="button" data-action="open-source" data-id="${esc(source.id)}">查看</button></div>`).join('')}</div>`; }
  function renderHistory() {
    const op=state.history.find(item=>item.id===selectedOperation)||state.history[0];if(!op)return '<div class="empty-view">暂无变更</div>';
    selectedOperation=op.id;selectedChange=Math.min(selectedChange,op.changes.length-1);const change=op.changes[selectedChange];
    return `<div class="view-header"><div><h1>变更</h1><p>一次操作、受影响资料与内容差异</p></div></div><div class="history-workspace"><div class="operation-list">${state.history.map(item=>`<button class="operation-item ${item.id===op.id?'active':''}" data-action="operation" data-id="${esc(item.id)}"><span class="operation-marker"></span><span><strong>${esc(item.title)}</strong><small>${esc(item.time)} · ${esc(item.actor)}</small><small>${item.changes.length} 张卡片</small></span></button>`).join('')}</div><div class="diff-area"><h2>${esc(op.title)}</h2><div class="diff-meta">${esc(op.actor)} · ${esc(op.time)} · 已完成</div><div class="affected-cards">${op.changes.map((item,index)=>`<button class="${index===selectedChange?'active':''}" data-action="select-change" data-index="${index}">${esc(item.title)}</button>`).join('')}</div><div class="diff-toolbar"><span>${esc(change.notes)}</span><button class="button ghost" data-action="toggle-diff">${diffUnified?'并排比较':'上下比较'}</button></div><div class="diff-versions ${diffUnified?'unified':''}"><div class="diff-column old"><div class="diff-heading">修改前 ${change.beforeRevision?`· 第 ${change.beforeRevision} 版`:'· 尚未创建'}</div><div class="diff-text">${esc(change.before||'无')}</div></div><div class="diff-column new"><div class="diff-heading">修改后 · 第 ${change.afterRevision} 版</div><div class="diff-text">${esc(change.after)}</div></div></div><div class="detail-context"><button class="button" data-action="open-card" data-id="${esc(change.cardId)}">打开当前卡片</button>${change.before?`<button class="button" data-action="restore-version" data-card="${esc(change.cardId)}">恢复为新修订</button>`:''}</div></div></div>`;
  }
  const graphNodes=[{id:'property',kind:'card',x:300,y:110,title:'房产资料在哪里',sub:'卡片 · 家庭'},{id:'property-text',kind:'source',x:90,y:275,title:'原始文字',sub:'本人输入'},{id:'property-image',kind:'source',x:510,y:275,title:'存放位置图片',sub:'位置示意图'},{id:'family',kind:'card',x:300,y:390,title:'一次家庭资料整理',sub:'卡片 · 待确认'},{id:'family-audio',kind:'source',x:90,y:480,title:'原始录音',sub:'合成播放示例'},{id:'family-video',kind:'source',x:510,y:480,title:'位置演示录像',sub:'合成播放示例'},{id:'network',kind:'card',x:700,y:110,title:'家庭网络维护',sub:'卡片 · 家庭'}];
  const graphEdges=[['property','property-text','来源'],['property','property-image','来源'],['property','family','相关资料'],['family','family-audio','来源'],['family','family-video','来源'],['property','network','同属家庭盒子']];
  function renderGraph() {
    return `<div class="view-header"><div><h1>资料关系</h1><p>点击节点打开资料；拖动节点调整图中位置</p></div><button class="button" data-action="graph-reset">恢复排列</button></div><div class="graph-wrap"><svg class="graph-canvas" viewBox="0 0 900 570" role="img" aria-label="示例卡片与原始资料之间的关系图">${graphEdges.map(([from,to,label])=>`<g data-edge-from="${from}" data-edge-to="${to}"><line class="graph-edge"/><text class="graph-edge-label" text-anchor="middle">${label}</text></g>`).join('')}${graphNodes.map(node=>`<g class="graph-node ${node.kind==='card'?'card-node':''} ${node.id===currentCardId?'selected':''}" data-node-id="${node.id}" transform="translate(${node.x},${node.y})" role="button" tabindex="0" aria-label="打开${node.title}"><rect x="-86" y="-30" width="172" height="61" rx="8"/><text text-anchor="middle" y="-3">${node.title}</text><text class="node-subtitle" text-anchor="middle" y="18">${node.sub}</text></g>`).join('')}</svg><div class="graph-list">${graphNodes.map(node=>`<button data-action="graph-open" data-id="${node.id}">${node.title} · ${node.sub}</button>`).join('')}</div><div class="graph-legend"><span>卡片与来源保持独立身份</span><span>收纳关系不改变可见范围</span></div></div>`;
  }
  function updateGraphEdges() {
    $$('.graph-canvas').forEach(svg=>{ $$('[data-edge-from]',svg).forEach(edge=>{const from=graphNodes.find(n=>n.id===edge.dataset.edgeFrom),to=graphNodes.find(n=>n.id===edge.dataset.edgeTo);const line=$('line',edge),text=$('text',edge);line.setAttribute('x1',from.x);line.setAttribute('y1',from.y);line.setAttribute('x2',to.x);line.setAttribute('y2',to.y);text.setAttribute('x',(from.x+to.x)/2);text.setAttribute('y',(from.y+to.y)/2-9);}); });
  }
  function viewMarkup(tab) {
    if(tab==='cards')return renderCatalog();if(tab==='sources')return renderSources();if(tab==='graph')return renderGraph();if(tab==='changes')return renderHistory();if(tab==='agent')return '';
    if(tab.startsWith('card:'))return renderDetail(tab.slice(5));if(tab.startsWith('source:'))return renderSource(tab.slice(7));return '';
  }
  function renderWorkspace() {
    $('#agentParking').append(agent);
    groupRoot.classList.toggle('split',state.groups.length>1);
    groupRoot.innerHTML=state.groups.map((group,index)=>`<section class="editor-group ${index===focusedGroup?'focused':''}" data-group="${index}"><header class="tabbar"><div class="tabs" role="tablist" aria-label="窗口组 ${index+1}">${group.tabs.map(tab=>{const info=tabInfo(tab);return `<div class="tab ${group.active===tab?'active':''}" role="tab" tabindex="${group.active===tab?'0':'-1'}" aria-selected="${group.active===tab}" aria-controls="view-${index}" draggable="true" data-tab="${esc(tab)}" data-group="${index}">${icon(info.icon)}<span class="tab-name">${esc(info.title)}</span><button class="close-tab" data-action="close-tab" data-tab="${esc(tab)}" data-group="${index}" aria-label="关闭${esc(info.title)}">${icon('close')}</button></div>`;}).join('')}</div><div class="group-actions"><button class="icon-button" data-action="add-view" data-group="${index}" aria-label="打开视图">${icon('plus')}</button><button class="icon-button" data-action="split" data-group="${index}" aria-label="${state.groups.length>1?'合并窗口组':'分屏查看'}">${icon('split')}</button><button class="icon-button" data-action="popout-tab" data-group="${index}" aria-label="独立窗口打开当前视图">${icon('external')}</button></div></header><div class="view" id="view-${index}" role="tabpanel">${group.tabs.length?viewMarkup(group.active):'<div class="empty-view"><h2>打开一个工作视图</h2><button class="button" data-action="nav" data-tab="cards">浏览资料</button></div>'}</div></section>`).join('');
    ['leftDock','rightDock','bottomDock','floatingWindow'].forEach(id=>$('#'+id).hidden=true);
    $('#leftResize').hidden=true;$('#rightResize').hidden=true;
    if(state.dock==='center'){
      const index=state.groups.findIndex(group=>group.active==='agent');
      if(index>=0){const view=$(`#view-${index}`);view.style.overflow='hidden';view.append(agent);}
    }else if(state.dock!=='hidden'){
      const destination={right:'rightDock',left:'leftDock',bottom:'bottomDock',floating:'floatingWindow'}[state.dock]||'rightDock';
      $('#'+destination).hidden=false;$('#'+destination).append(agent);
      if(state.dock==='right')$('#rightResize').hidden=false;if(state.dock==='left')$('#leftResize').hidden=false;
    }
    $('#workspaceMode').value=state.mode;renderNavigation();updateGraphEdges();renderContexts();
    const activeTab=state.groups[focusedGroup]?.active||'cards';
    $$('#activityBar [data-tab]').forEach(button=>button.classList.toggle('active',button.dataset.tab===(activeTab.startsWith('card:')?'cards':activeTab.startsWith('source:')?'sources':activeTab)));
  }
  function openTab(tab,{side=false,group=focusedGroup}={}) {
    if(innerWidth<=700&&tab!=='agent')state.dock='hidden';
    if(side){if(state.groups.length<2)state.groups.push({tabs:[],active:tab});group=1;}
    group=Math.min(group,state.groups.length-1);const target=state.groups[group];
    if(!target.tabs.includes(tab))target.tabs.push(tab);target.active=tab;focusedGroup=group;
    if(tab.startsWith('card:'))currentCardId=tab.slice(5);
    if(tab==='agent')state.dock='center';
    renderWorkspace();persist();
  }
  function setDock(dock) {
    state.dock=dock;
    if(dock==='center'){const target=state.groups[0];if(!target.tabs.includes('agent'))target.tabs.push('agent');target.active='agent';focusedGroup=0;}
    else state.groups.forEach(group=>{group.tabs=group.tabs.filter(tab=>tab!=='agent');if(group.active==='agent')group.active=group.tabs[0]||'cards';});
    renderWorkspace();persist();
  }
  function setMode(mode) { state.mode=mode;state.groups=defaultGroups(mode);state.dock=mode==='assistant'?'center':innerWidth<=700?'hidden':'right';focusedGroup=0;renderWorkspace();persist(); }
  function splitGroup(index) {
    if(state.groups.length>1){state.groups[0].tabs=[...new Set(state.groups.flatMap(g=>g.tabs))];state.groups=[state.groups[0]];focusedGroup=0;}
    else {const current=state.groups[0];let tab=current.active;if(current.tabs.length>1)current.tabs=current.tabs.filter(t=>t!==tab);else tab='sources';current.active=current.tabs[0];state.groups.push({tabs:[tab],active:tab});focusedGroup=1;}
    renderWorkspace();persist();
  }
  function closeTab(tab,index) {
    const group=state.groups[index];group.tabs=group.tabs.filter(item=>item!==tab);if(group.active===tab)group.active=group.tabs.at(-1)||'cards';
    if(tab==='agent'&&state.dock==='center')state.dock='hidden';
    if(!group.tabs.length&&state.groups.length>1){state.groups.splice(index,1);focusedGroup=0;}
    renderWorkspace();persist();
  }
  function showPopover(anchor,html) {
    const pop=$('#popover');pop.innerHTML=html;pop.hidden=false;
    const rect=anchor.getBoundingClientRect();pop.style.left='0px';pop.style.top='0px';
    const width=pop.offsetWidth,height=pop.offsetHeight;
    pop.style.left=`${Math.max(10,Math.min(rect.left,innerWidth-width-10))}px`;
    pop.style.top=`${Math.max(10,rect.bottom+height<innerHeight-10?rect.bottom+6:rect.top-height-6)}px`;
  }
  function hidePopover(){ $('#popover').hidden=true; }
  function showModal(title,body,footer='') {
    $('#modalContent').innerHTML=`<header class="modal-header"><h2>${esc(title)}</h2><button class="icon-button" data-action="close-modal" aria-label="关闭">${icon('close')}</button></header><div class="modal-body">${body}</div>${footer?`<footer class="modal-footer">${footer}</footer>`:''}`;
    if(!$('#modal').open)$('#modal').showModal();
  }
  function showSettings(tab='providers') {
    const providerContent=`<div class="settings-note">这些配置用于演示选择流程，不连接服务，也不需要真实 API Key。</div>${state.providers.map(provider=>`<div class="provider-row"><span class="provider-avatar">${esc(provider.name.slice(0,1))}</span><div><strong>${esc(provider.name)}</strong><p>${esc(provider.protocol)} · ${provider.connected?'示例已配置':'待配置'}</p></div><button class="button" data-action="configure-provider" data-id="${esc(provider.id)}">配置</button></div>`).join('')}<div class="detail-context"><button class="button" data-action="add-provider">${icon('plus')}添加提供方</button></div>`;
    const speechContent=`<label class="field">语音识别方式<select id="speechChoice"><option value="local" ${state.speech==='local'?'selected':''}>本地识别 · SenseVoice（演示）</option><option value="cloud" ${state.speech==='cloud'?'selected':''}>云端识别 · 自定义服务（演示）</option></select></label><label class="field">识别语言<select><option>自动识别</option><option>中文</option><option>English</option></select></label><p>麦克风按钮会演示录音条、计时与文字回填。此 Demo 不访问麦克风，不执行真实识别。</p><p>真实录音与录像可以通过“添加本地资料”选择并播放。</p>`;
    const layoutContent=`<label class="field">启动后的默认工作台<select id="homeChoice"><option value="ask" ${!state.home?'selected':''}>每次询问</option><option value="library" ${state.home==='library'?'selected':''}>资料工作台</option><option value="assistant" ${state.home==='assistant'?'selected':''}>助手工作台</option></select></label><label class="field">助手面板位置<select id="dockChoice">${[['right','右侧'],['left','左侧'],['bottom','底部'],['center','中央标签'],['floating','浮动窗口'],['hidden','收起']].map(([value,label])=>`<option value="${value}" ${state.dock===value?'selected':''}>${label}</option>`).join('')}</select></label><p>标签可以拖到另一窗口组；助手可以停靠、浮动或独立打开。</p><button class="button" data-action="reset-demo">重置示例资料与布局</button>`;
    $('#modalContent').innerHTML=`<header class="modal-header"><h2>工作台设置</h2><button class="icon-button" data-action="close-modal" aria-label="关闭">${icon('close')}</button></header><nav class="settings-tabs" aria-label="设置分类">${[['providers','AI 提供方'],['speech','语音'],['layout','布局与启动']].map(([value,label])=>`<button class="${tab===value?'active':''}" data-action="settings-tab" data-tab="${value}">${label}</button>`).join('')}</nav><div class="modal-body">${tab==='providers'?providerContent:tab==='speech'?speechContent:layoutContent}</div><footer class="modal-footer"><button class="button primary" data-action="save-settings" data-tab="${tab}">完成</button></footer>`;
    if(!$('#modal').open)$('#modal').showModal();
  }
  function providerEditor(id) {
    const provider=state.providers.find(item=>item.id===id);
    showModal(provider?'配置提供方':'添加提供方',`<label class="field">显示名称<input id="providerName" value="${esc(provider?.name||'')}" placeholder="例如：我的 API 服务"></label><label class="field">服务地址<input id="providerEndpoint" type="url" value="${esc(provider?.endpoint||'')}" placeholder="https://example.invalid/v1"></label><label class="field">接口方式<select id="providerProtocol">${['Responses','Chat Completions','兼容 API'].map(value=>`<option ${provider?.protocol===value?'selected':''}>${value}</option>`).join('')}</select></label><label class="field">模型名称<input id="providerModel" value="${esc(provider?.models.join(', ')||'')}" placeholder="多个模型用逗号分隔"></label><label class="field">API Key<input type="password" placeholder="仅用于演示，请勿填写真实密钥" autocomplete="off"></label><div class="settings-note">密钥输入不会保存；连接状态为模拟。</div>`,`<button class="button" data-action="settings-tab" data-tab="providers">返回</button><button class="button primary" data-action="save-provider" data-id="${esc(id||'')}">保存示例配置</button>`);
  }
  function modelMenu() {
    showPopover($('#modelButton'),`<div class="popover-title">选择本次会话的模型</div><input class="model-search" id="modelSearch" type="search" placeholder="搜索提供方或模型" aria-label="搜索模型">${state.providers.filter(p=>p.connected).map(provider=>`<div class="model-provider">${esc(provider.name)}</div>${provider.models.map(model=>`<button class="menu-item model-option ${state.model.providerId===provider.id&&state.model.name===model?'active':''}" data-action="select-model" data-provider="${esc(provider.id)}" data-model="${esc(model)}">${icon('chat')}<span>${esc(model)}</span>${state.model.providerId===provider.id&&state.model.name===model?icon('check'):''}</button>`).join('')}`).join('')}<hr><button class="menu-item" data-action="settings">${icon('plus')}管理提供方</button><div class="model-caption">切换从下一次发送生效 · 演示模式</div>`);
    $('#modelSearch').focus();
  }
  function renderModel(){ const provider=state.providers.find(p=>p.id===state.model.providerId);$('#modelButton').innerHTML=`<span>${esc(provider?.name||'提供方')} / ${esc(state.model.name)}</span>${icon('chevron')}`; }
  function renderContexts(){ $('#contextChips').innerHTML=contexts.filter(id=>cardById(id)).map(id=>`<span class="context-chip">${icon('file')}<span>${esc(cardById(id).title)}</span><button data-action="remove-context" data-id="${esc(id)}" aria-label="移除引用">${icon('close')}</button></span>`).join(''); }
  function renderMessages() {
    $('#messages').innerHTML=messages.length?messages.map(message=>`<div class="message ${message.role}"><div class="message-label">${message.role==='assistant'?icon('chat'):'本人'}${message.role==='assistant'?esc(message.model||'助手'):''}</div><div class="message-text">${esc(message.text)}</div>${message.proposal?renderProposal(message.proposal):''}</div>`).join(''):`<div class="message-welcome"><h2>从一件想整理的事开始</h2><p>可以记录新资料，也可以引用已有卡片。建议先核对，确认后在工作台中呈现。</p><div class="quick-prompts"><button class="quick-prompt" data-action="quick-prompt" data-prompt="帮我把这段家庭资料整理为卡片：保险单放在书房第二层抽屉，之后需要核对有效期。">整理一段新资料</button><button class="quick-prompt" data-action="reference" data-id="property">一起核对房产资料卡片</button><button class="quick-prompt" data-action="quick-prompt" data-prompt="请记录家庭网络维护：路由器在电视柜后面，重启之后等待两分钟。">记录家庭网络维护</button></div></div>`;
    $('#messages').scrollTop=$('#messages').scrollHeight;
  }
  function renderProposal(proposal) {
    if(proposal.saved)return `<div class="proposal saved"><div class="proposal-header">${icon('check')} 已保存并收纳</div><div class="proposal-saved-content">${esc(proposal.title)}<br><span class="source-note">${esc(proposal.box)} · ${esc(proposal.policy)}</span></div><div class="proposal-actions"><button class="button" data-action="open-card" data-id="${esc(proposal.cardId)}">打开卡片</button><button class="button" data-action="nav" data-tab="changes">查看变更</button></div></div>`;
    return `<div class="proposal" data-proposal="${proposal.id}"><div class="proposal-header"><span>${proposal.targetId?'修改卡片':'新建卡片'} · 待本人确认</span><span>可编辑</span></div><div class="proposal-body"><label>标题<input data-proposal-field="title" value="${esc(proposal.title)}"></label><label>总结<textarea data-proposal-field="summary">${esc(proposal.summary)}</textarea></label><label>收纳盒子<select data-proposal-field="box">${[...new Set(['家庭','个人',proposal.box])].map(box=>`<option ${box===proposal.box?'selected':''}>${esc(box)}</option>`).join('')}</select></label><label>可见范围<select data-proposal-field="policy"><option>仅本人</option></select></label><div class="source-note">${proposal.targetId?'保留已有来源与修订':'原始文字将作为来源保留'}</div></div><div class="proposal-actions"><button class="button primary" data-action="save-proposal" data-id="${proposal.id}">确认保存并收纳</button><button class="button ghost" data-action="dismiss-proposal" data-id="${proposal.id}">暂不保存</button></div></div>`;
  }
  function sendMessage() {
    const input=$('#composer'),text=input.value.trim();if(!text||voiceActive)return;
    const boundContexts=[...contexts],model=clone(state.model),provider=state.providers.find(p=>p.id===model.providerId);
    messages.push({role:'user',text});input.value='';$('#sendButton').disabled=true;renderMessages();
    sendTimer=setTimeout(()=>{
      const target=boundContexts.map(cardById).find(Boolean),isNetwork=text.includes('网络')||text.includes('路由器');
      const proposal={id:`proposal-${Date.now()}`,targetId:target?.id,title:target?target.title:isNetwork?'家庭网络维护记录':text.includes('保险')?'保险资料在哪里':'新的资料记录',summary:target?`${target.summary}\n\n补充：${text}`:text.replace(/^.*?[：:]/,''),box:target?.box||(text.includes('家庭')||text.includes('保险')||isNetwork?'家庭':'个人'),policy:'仅本人',sourceText:text};
      messages.push({role:'assistant',model:`${provider?.name} / ${model.name}`,text:target?'下面是修改建议。可以直接编辑总结，确认后保留为新修订。':'我准备了一张卡片，原始文字会保留在来源中。你可以修改标题、总结和收纳位置。',proposal});
      $('#sendButton').disabled=false;renderMessages();toast('已生成示例建议，等待本人确认');
    },550);
  }
  function saveProposal(id) {
    const proposal=messages.find(m=>m.proposal?.id===id)?.proposal;if(!proposal||proposal.saved)return;
    if(!proposal.title.trim()||!proposal.summary.trim()){toast('请填写标题与总结');return;}
    const target=proposal.targetId?cardById(proposal.targetId):null;
    if(target){updateCard(target,{title:proposal.title.trim(),summary:proposal.summary.trim(),box:proposal.box,policy:proposal.policy},'确认助手修改建议','AI 建议 · 本人确认');proposal.cardId=target.id;}
    else {
      const sourceId=`agent-source-${Date.now()}`,cardId=`agent-card-${Date.now()}`;
      const source={id:sourceId,type:'text',name:'对话原始文字.txt',text:proposal.sourceText,description:'本人输入 · 演示会话原文',time:'刚刚'};sources.push(source);
      const card={id:cardId,title:proposal.title.trim(),summary:proposal.summary.trim(),box:proposal.box,tags:['对话整理'],status:'已确认',revision:1,sources:[sourceId],policy:'仅本人',updated:'刚刚',agentSource:source};state.cards.unshift(card);
      state.history.unshift({id:`change-${Date.now()}`,title:'确认助手卡片并收纳',actor:'AI 建议 · 本人确认',time:'刚刚',changes:[{cardId,title:card.title,before:'',after:card.summary,beforeRevision:0,afterRevision:1,notes:`新建卡片 · 收纳到${card.box} · 仅本人`} ]});proposal.cardId=cardId;
    }
    proposal.saved=true;selectedOperation=state.history[0].id;selectedChange=0;renderMessages();renderWorkspace();persist();toast('已保存卡片、原始文字与本次变更');
  }
  function updateCard(card,patch,title='修改资料卡片',actor='本人修改') {
    const before=card.summary,beforeRevision=card.revision,oldBox=card.box;Object.assign(card,patch);card.revision++;card.updated='刚刚';
    state.history.unshift({id:`change-${Date.now()}`,title,actor,time:'刚刚',ephemeral:card.ephemeral,changes:[{cardId:card.id,title:card.title,before,after:card.summary,beforeRevision,afterRevision:card.revision,notes:`${oldBox===card.box?'收纳保持'+card.box:`收纳从${oldBox}改为${card.box}`} · ${card.policy}`} ]});selectedOperation=state.history[0].id;selectedChange=0;
  }
  function editCard(id) {
    const card=cardById(id);showModal(card?'编辑卡片':'新建卡片',`<label class="field">标题<input id="editTitle" value="${esc(card?.title||'')}" placeholder="让标题说清这张卡片是什么"></label><label class="field">总结内容<textarea id="editSummary" placeholder="写下可独立理解的内容">${esc(card?.summary||'')}</textarea></label><label class="field">收纳盒子<input id="editBox" value="${esc(card?.box||'个人')}"></label><label class="field">标签<input id="editTags" value="${esc(card?.tags.join('，')||'')}" placeholder="用逗号分隔"></label><div class="settings-note">原始资料链接保留；修改会记录为新修订。</div>`,`<button class="button" data-action="close-modal">取消</button><button class="button primary" data-action="save-card" data-id="${esc(id||'')}">保存卡片</button>`);
  }
  function saveCard(id) {
    const patch={title:$('#editTitle').value.trim(),summary:$('#editSummary').value.trim(),box:$('#editBox').value.trim()||'个人',tags:$('#editTags').value.split(/[,，]/).map(t=>t.trim()).filter(Boolean)};
    if(!patch.title||!patch.summary){toast('请填写标题与总结');return;}
    let card=cardById(id);
    if(card)updateCard(card,patch);
    else {const source={id:`manual-source-${Date.now()}`,type:'text',name:'本人输入原文.txt',text:patch.summary,description:'本人输入 · 演示原文',time:'刚刚'};sources.push(source);card={id:`manual-card-${Date.now()}`,...patch,status:'已确认',revision:1,sources:[source.id],policy:'仅本人',updated:'刚刚',agentSource:source};state.cards.unshift(card);state.history.unshift({id:`change-${Date.now()}`,title:'手动创建卡片',actor:'本人输入',time:'刚刚',changes:[{cardId:card.id,title:card.title,before:'',after:card.summary,beforeRevision:0,afterRevision:1,notes:`收纳到${card.box} · 仅本人`} ]});}
    $('#modal').close();renderWorkspace();persist();toast('卡片与修订已保存');
  }
  function startVoice() {
    if(voiceActive){stopVoice(false);return;}voiceActive=true;voiceStart=Date.now();$('#voiceStrip').hidden=false;$('#voiceTime').textContent='00:00';$('#micButton').style.color='var(--accent)';$('#composer').disabled=true;
    voiceTimer=setInterval(()=>{const seconds=Math.floor((Date.now()-voiceStart)/1000);$('#voiceTime').textContent=`${String(Math.floor(seconds/60)).padStart(2,'0')}:${String(seconds%60).padStart(2,'0')}`;if(seconds>=60)stopVoice(false);},250);
    toast('语音条演示已开始；未访问麦克风');
  }
  function stopVoice(cancel) {
    if(!voiceActive)return;voiceActive=false;clearInterval(voiceTimer);$('#voiceStrip').hidden=true;$('#micButton').style.color='';$('#composer').disabled=false;
    if(!cancel){$('#composer').value=[$('#composer').value,'请把这段家庭资料整理成卡片，放到家庭盒子里。'].filter(Boolean).join('\n');$('#composer').focus();toast('示例语音文字已回填，可以编辑后发送');}else toast('已取消语音演示');
  }
  function popoutView(tab) {
    const url=new URL(location.href);url.search='';if(params.has('qa'))url.searchParams.set('qa','1');url.searchParams.set('popout',tab==='agent'?'agent':'view');if(tab!=='agent')url.searchParams.set('view',tab);
    const source=tab.startsWith('source:')?sourceById(tab.slice(7)):null;
    if(source?.ephemeral){toast('临时导入文件请在当前窗口查看');return;}
    const opened=window.open(url.href,'_blank','popup,width=980,height=760');if(!opened)toast('浏览器阻止了新窗口，可允许弹出窗口后重试');
  }
  function openGraphNode(id) { if(cardById(id))openTab('card:'+id,{side:true});else if(sourceById(id))openTab('source:'+id,{side:true}); }
  function beginImport() { $('#fileInput').click(); }
  async function importFiles(files) {
    const active=state.groups[focusedGroup]?.active,target=active?.startsWith('card:')?cardById(active.slice(5)):null;
    for(const file of files){
      const type=file.type.startsWith('image/')?'image':file.type.startsWith('audio/')?'audio':file.type.startsWith('video/')?'video':/\.(txt|md)$/i.test(file.name)?'text':null;
      if(!type){toast('支持图片、录音、录像和文字文件');continue;}
      if(type==='text'&&file.size>1024*1024){toast('文字演示文件请小于 1 MB');continue;}
      const source={id:`import-${Date.now()}-${Math.random().toString(36).slice(2,6)}`,type,name:file.name,time:'本次会话',description:'本地选择 · 刷新后需重新添加',ephemeral:true,url:URL.createObjectURL(file)};
      if(type==='text')source.text=await file.text();sources.push(source);
      if(target){target.sources.push(source.id);}
      else state.cards.unshift({id:'card-'+source.id,title:file.name,summary:'已关联原始资料。可以编辑标题和总结，再继续收纳。',box:'个人',tags:['本次导入'],status:'待确认',revision:1,sources:[source.id],policy:'仅本人',updated:'刚刚',ephemeral:true});
    }
    renderWorkspace();toast(target?'已添加到当前卡片；导入文件仅保留在本次浏览器会话':'已添加本地资料，可以展开查看或播放');$('#fileInput').value='';
  }
  function restoreVersion() {
    const op=state.history.find(item=>item.id===selectedOperation),change=op?.changes[selectedChange],card=cardById(change?.cardId);if(!card||!change.before)return;
    updateCard(card,{summary:change.before},'恢复旧内容为新修订');$('#modal').close();renderWorkspace();persist();toast('已生成新修订，原有历史仍保留');
  }

  const actions={
    nav(element){let tab=element.dataset.tab;if(tab==='cards-draft'){currentFilter='待确认';tab='cards';}else if(tab==='cards')currentFilter='全部';openTab(tab);},
    filter(element){currentFilter=element.dataset.filter;openTab('cards');},
    'open-card'(element){openTab('card:'+element.dataset.id);},
    'open-source'(element){openTab('source:'+element.dataset.id,{side:true});},
    preview(element){const key=`${element.dataset.card}:${element.dataset.source}`;previews.has(key)?previews.delete(key):previews.add(key);renderWorkspace();},
    'close-tab'(element){closeTab(element.dataset.tab,Number(element.dataset.group));},
    'add-view'(element){showPopover(element,`<div class="popover-title">打开工作视图</div>${['cards','agent','graph','changes','sources'].map(tab=>`<button class="menu-item" data-action="nav" data-tab="${tab}">${icon(tabInfo(tab).icon)}${tabInfo(tab).title}</button>`).join('')}`);focusedGroup=Number(element.dataset.group);},
    split(element){splitGroup(Number(element.dataset.group));},
    'popout-tab'(element){popoutView(state.groups[Number(element.dataset.group)].active);},
    'popout-source'(element){popoutView('source:'+element.dataset.id);},
    'show-agent'(){setDock(innerWidth<=700?'center':'right');},
    dock(element){setDock(element.dataset.dock);},
    settings(){hidePopover();showSettings();},
    'settings-tab'(element){showSettings(element.dataset.tab);},
    'close-modal'(){ $('#modal').close(); },
    'configure-provider'(element){providerEditor(element.dataset.id);},
    'add-provider'(){providerEditor();},
    'save-provider'(element){const name=$('#providerName').value.trim(),endpoint=$('#providerEndpoint').value.trim(),models=$('#providerModel').value.split(/[,，]/).map(m=>m.trim()).filter(Boolean);if(!name||!endpoint||!models.length){toast('请填写名称、地址和模型');return;}let provider=state.providers.find(p=>p.id===element.dataset.id);if(!provider){provider={id:'provider-'+Date.now()};state.providers.push(provider);}Object.assign(provider,{name,endpoint,models,protocol:$('#providerProtocol').value,connected:true});persist();showSettings();renderModel();toast('示例提供方已保存，模型选择器中可以切换');},
    'save-settings'(element){if(element.dataset.tab==='speech')state.speech=$('#speechChoice').value;if(element.dataset.tab==='layout'){state.home=$('#homeChoice').value==='ask'?null:$('#homeChoice').value;setDock($('#dockChoice').value);}persist();$('#modal').close();},
    'select-model'(element){state.model={providerId:element.dataset.provider,name:element.dataset.model};renderModel();persist();toast('模型已切换，从下一次演示消息生效');},
    'new-card'(){editCard();},
    'edit-card'(element){editCard(element.dataset.id);},
    'save-card'(element){saveCard(element.dataset.id);},
    'confirm-card'(element){const card=cardById(element.dataset.id);if(card&&card.status!=='已确认'){updateCard(card,{status:'已确认'},'本人确认资料卡片');renderWorkspace();persist();toast('已确认，并保留来源与历史');}},
    'card-history'(element){const op=state.history.find(item=>item.changes.some(change=>change.cardId===element.dataset.id));if(op){selectedOperation=op.id;selectedChange=op.changes.findIndex(c=>c.cardId===element.dataset.id);}openTab('changes',{side:true});},
    'card-graph'(element){currentCardId=element.dataset.id;openTab('graph',{side:true});},
    reference(element){const id=element.dataset.id||currentCardId;if(cardById(id)&&!contexts.includes(id))contexts.push(id);if(state.dock==='hidden')setDock(innerWidth<=700?'center':'right');renderContexts();$('#composer').focus();toast('已引用卡片；浏览其他资料不会改变这次引用');},
    'remove-context'(element){contexts=contexts.filter(id=>id!==element.dataset.id);renderContexts();},
    'quick-prompt'(element){$('#composer').value=element.dataset.prompt;$('#composer').focus();},
    'save-proposal'(element){saveProposal(element.dataset.id);},
    'dismiss-proposal'(element){const message=messages.find(m=>m.proposal?.id===element.dataset.id);if(message){delete message.proposal;message.text+='\n本次建议暂未保存。';}renderMessages();},
    operation(element){selectedOperation=element.dataset.id;selectedChange=0;renderWorkspace();},
    'select-change'(element){selectedChange=Number(element.dataset.index);renderWorkspace();},
    'toggle-diff'(){diffUnified=!diffUnified;renderWorkspace();},
    'restore-version'(){showModal('恢复为新修订','<p>用所选旧内容生成一个新版本。当前版本与之前的历史都会保留。</p>','<button class="button" data-action="close-modal">取消</button><button class="button primary" data-action="confirm-restore">确认恢复</button>');},
    'confirm-restore'(){restoreVersion();},
    'graph-reset'(){const positions=[[300,110],[90,275],[510,275],[300,390],[90,480],[510,480],[700,110]];graphNodes.forEach((node,index)=>{[node.x,node.y]=positions[index];});renderWorkspace();},
    'graph-open'(element){openGraphNode(element.dataset.id);},
    import(){beginImport();},
    'reset-demo'(){showModal('重置演示','<p>恢复虚构示例资料和默认布局。不会访问 LiveRelay 应用的真实资料库。</p>','<button class="button" data-action="close-modal">取消</button><button class="button primary" data-action="confirm-reset">重置演示</button>');},
    'confirm-reset'(){localStorage.removeItem(storageKey);location.href=location.pathname+(params.has('qa')?'?qa=1':'');},
    unlock(){ $('#modal').close(); },
  };
  document.addEventListener('click',event=>{
    const element=event.target.closest('[data-action]');if(element){event.stopPropagation();const action=element.dataset.action;actions[action]?.(element);if(!['add-view'].includes(action))hidePopover();return;}
    const tab=event.target.closest('.tab');if(tab){focusedGroup=Number(tab.dataset.group);state.groups[focusedGroup].active=tab.dataset.tab;renderWorkspace();persist();return;}
    const node=event.target.closest('[data-node-id]');if(node){if(suppressGraphClick){suppressGraphClick=false;return;}openGraphNode(node.dataset.nodeId);return;}
    if(!event.target.closest('#popover')&&event.target!==$('#modelButton')&&!$('#modelButton').contains(event.target))hidePopover();
  });
  document.addEventListener('input',event=>{
    if(event.target.dataset.proposalField){const parent=event.target.closest('[data-proposal]'),proposal=messages.find(m=>m.proposal?.id===parent.dataset.proposal)?.proposal;if(proposal)proposal[event.target.dataset.proposalField]=event.target.value;}
    if(event.target.id==='modelSearch'){const query=event.target.value.toLowerCase();$$('.model-option').forEach(option=>option.hidden=!`${option.dataset.provider} ${option.dataset.model}`.toLowerCase().includes(query));}
  });
  document.addEventListener('change',event=>{if(event.target.dataset.proposalField){const parent=event.target.closest('[data-proposal]'),proposal=messages.find(m=>m.proposal?.id===parent.dataset.proposal)?.proposal;if(proposal)proposal[event.target.dataset.proposalField]=event.target.value;}});
  document.addEventListener('keydown',event=>{
    const tab=event.target.closest('.tab');if(tab&&['Enter',' ','ArrowLeft','ArrowRight'].includes(event.key)){event.preventDefault();const index=Number(tab.dataset.group),group=state.groups[index];let selected=tab.dataset.tab;if(event.key.startsWith('Arrow')){const current=group.tabs.indexOf(selected);selected=group.tabs[(current+(event.key==='ArrowRight'?1:-1)+group.tabs.length)%group.tabs.length];}focusedGroup=index;group.active=selected;renderWorkspace();$(`.tab[data-group="${index}"][data-tab="${CSS.escape(selected)}"]`)?.focus();persist();}
    const node=event.target.closest('[data-node-id]');if(node&&['Enter',' '].includes(event.key)){event.preventDefault();openGraphNode(node.dataset.nodeId);}
  });
  $('#composer').addEventListener('keydown',event=>{if((event.ctrlKey||event.metaKey)&&event.key==='Enter'){event.preventDefault();sendMessage();}});
  $('#searchInput').addEventListener('input',event=>{searchQuery=event.target.value;if(!state.groups.some(group=>group.active==='cards'))openTab('cards');else renderWorkspace();});
  $('#workspaceMode').addEventListener('change',event=>setMode(event.target.value));
  $('#themeButton').addEventListener('click',()=>{state.theme=state.theme==='dark'?'light':'dark';applyTheme();persist();});
  $('#settingsButton').addEventListener('click',()=>showSettings());
  $('#startupButton').addEventListener('click',()=>{$('#rememberStartup').checked=!!state.home;$('#startupModal').showModal();});
  $('#hideNavigator').addEventListener('click',()=>{state.navigatorHidden=true;renderNavigation();persist();});
  $('#importButton').addEventListener('click',beginImport);
  $('#fileInput').addEventListener('change',event=>importFiles([...event.target.files]));
  $('#attachButton').addEventListener('click',()=>actions.reference({dataset:{id:currentCardId}}));
  $('#micButton').addEventListener('click',startVoice);$('#stopVoice').addEventListener('click',()=>stopVoice(false));$('#cancelVoice').addEventListener('click',()=>stopVoice(true));
  $('#sendButton').addEventListener('click',sendMessage);$('#modelButton').addEventListener('click',modelMenu);
  $('#agentLayoutButton').addEventListener('click',event=>{event.stopPropagation();showPopover(event.currentTarget,`<div class="popover-title">移动助手面板</div>${[['right','停靠到右侧'],['left','停靠到左侧'],['bottom','停靠到底部'],['center','在中央标签打开'],['floating','浮动窗口']].map(([dock,label])=>`<button class="menu-item ${state.dock===dock?'active':''}" data-action="dock" data-dock="${dock}">${icon('panel')}${label}</button>`).join('')}`);});
  $('#agentPopoutButton').addEventListener('click',()=>popoutView('agent'));
  $('#agentCloseButton').addEventListener('click',()=>setDock('hidden'));
  $('#newConversation').addEventListener('click',()=>{clearTimeout(sendTimer);$('#sendButton').disabled=false;messages=[];contexts=[];renderMessages();renderContexts();toast('已打开新演示会话');});
  $('#lockButton').addEventListener('click',()=>{stopVoice(true);showModal('工作台已锁定（演示）','<p>实际应用中，所有资料视图与助手上下文应同时锁定。</p>','<button class="button primary" data-action="unlock">返回示例工作台</button>');});
  $$('[data-start]').forEach(button=>button.addEventListener('click',()=>{const mode=button.dataset.start;state.home=$('#rememberStartup').checked?mode:null;setMode(mode);$('#startupModal').close();persist();}));

  document.addEventListener('dragstart',event=>{
    const tab=event.target.closest('.tab');if(tab){dragTab={tab:tab.dataset.tab,from:Number(tab.dataset.group)};event.dataTransfer.setData('application/liverelay-tab',JSON.stringify(dragTab));event.dataTransfer.effectAllowed='move';return;}
    const card=event.target.closest('[data-card-drag]');if(card){event.dataTransfer.setData('application/liverelay-card',card.dataset.cardDrag);event.dataTransfer.effectAllowed='copy';}
  });
  document.addEventListener('dragover',event=>{const group=event.target.closest('.editor-group'),composer=event.target.closest('.composer-area');if(group&&dragTab||composer&&event.dataTransfer.types.includes('application/liverelay-card')){event.preventDefault();(composer||group).classList.add('drop-target');}});
  document.addEventListener('dragleave',event=>{const target=event.target.closest('.drop-target');if(target&&!target.contains(event.relatedTarget))target.classList.remove('drop-target');});
  document.addEventListener('drop',event=>{
    $$('.drop-target').forEach(node=>node.classList.remove('drop-target'));
    const composer=event.target.closest('.composer-area'),cardId=event.dataTransfer.getData('application/liverelay-card');if(composer&&cardId){event.preventDefault();actions.reference({dataset:{id:cardId}});return;}
    const groupElement=event.target.closest('.editor-group');if(groupElement&&dragTab){event.preventDefault();const to=Number(groupElement.dataset.group),from=dragTab.from,tab=dragTab.tab;const source=state.groups[from],target=state.groups[to];source.tabs=source.tabs.filter(t=>t!==tab);target.tabs=target.tabs.filter(t=>t!==tab);const onto=event.target.closest('.tab')?.dataset.tab,position=onto?target.tabs.indexOf(onto):-1;if(position>=0)target.tabs.splice(position,0,tab);else target.tabs.push(tab);target.active=tab;if(source.active===tab&&from!==to)source.active=source.tabs[0]||'cards';focusedGroup=to;dragTab=null;renderWorkspace();persist();}
  });
  document.addEventListener('dragend',()=>{dragTab=null;$$('.drop-target').forEach(node=>node.classList.remove('drop-target'));});
  ['leftResize','rightResize'].forEach(id=>$('#'+id).addEventListener('pointerdown',event=>{const start=event.clientX,width=$('#'+(id==='leftResize'?'leftDock':'rightDock')).getBoundingClientRect().width;const move=e=>document.documentElement.style.setProperty('--agent-width',`${Math.max(280,Math.min(innerWidth*.6,width+(e.clientX-start)*(id==='leftResize'?1:-1)))}px`);const end=()=>{document.removeEventListener('pointermove',move);document.removeEventListener('pointerup',end);};document.addEventListener('pointermove',move);document.addEventListener('pointerup',end);}));
  $('#agentHeading').addEventListener('pointerdown',event=>{if(state.dock!=='floating'||event.target.closest('button'))return;const windowElement=$('#floatingWindow'),rect=windowElement.getBoundingClientRect(),x=event.clientX,y=event.clientY;const move=e=>{windowElement.style.left=`${Math.max(0,Math.min(innerWidth-windowElement.offsetWidth,rect.left+e.clientX-x))}px`;windowElement.style.top=`${Math.max(0,Math.min(innerHeight-60,rect.top+e.clientY-y))}px`;};const end=()=>{document.removeEventListener('pointermove',move);document.removeEventListener('pointerup',end);};document.addEventListener('pointermove',move);document.addEventListener('pointerup',end);});
  document.addEventListener('pointerdown',event=>{
    const nodeElement=event.target.closest('[data-node-id]');if(!nodeElement)return;event.preventDefault();const svg=nodeElement.closest('svg'),node=graphNodes.find(n=>n.id===nodeElement.dataset.nodeId),startX=event.clientX,startY=event.clientY,original={x:node.x,y:node.y};let moved=false;
    const transformPoint=e=>new DOMPoint(e.clientX,e.clientY).matrixTransform(svg.getScreenCTM().inverse());const start=transformPoint(event);
    const move=e=>{if(Math.abs(e.clientX-startX)+Math.abs(e.clientY-startY)>5)moved=true;if(!moved)return;const point=transformPoint(e);node.x=Math.max(88,Math.min(812,original.x+point.x-start.x));node.y=Math.max(35,Math.min(535,original.y+point.y-start.y));$$(`[data-node-id="${node.id}"]`).forEach(element=>element.setAttribute('transform',`translate(${node.x},${node.y})`));updateGraphEdges();};
    const end=()=>{document.removeEventListener('pointermove',move);document.removeEventListener('pointerup',end);if(moved)suppressGraphClick=true;};document.addEventListener('pointermove',move);document.addEventListener('pointerup',end);
  });
  window.addEventListener('storage',event=>{if(event.key!==storageKey||!event.newValue)return;try{const update=JSON.parse(event.newValue);state.cards=update.cards;state.history=update.history;state.providers=update.providers;state.theme=update.theme;state.model=update.model;state.cards.forEach(card=>{if(card.agentSource&&!sourceById(card.agentSource.id))sources.push(card.agentSource);});applyTheme();renderModel();renderWorkspace();}catch{}});
  window.addEventListener('beforeunload',()=>{sources.filter(s=>s.ephemeral&&s.url).forEach(source=>URL.revokeObjectURL(source.url));});

  $('#activityBar').innerHTML=[['cards','grid','资料'],['agent','chat','助手'],['graph','graph','关系'],['changes','history','变更'],['sources','folder','原始资料']].map(([tab,ico,title])=>`<button data-action="${tab==='agent'?'show-agent':'nav'}" data-tab="${tab}" aria-label="${title}" title="${title}">${icon(ico)}</button>`).join('')+`<button id="toggleNavigator" aria-label="展开或收起资料导航" title="资料导航">${icon('panel')}</button>`;
  $('#toggleNavigator').addEventListener('click',()=>{if(innerWidth<=950)$('#shell').classList.toggle('navigator-mobile-open');else {state.navigatorHidden=!state.navigatorHidden;renderNavigation();persist();}});
  $('#settingsButton').innerHTML=icon('settings');$('#lockButton').innerHTML=icon('lock');$('#hideNavigator').innerHTML=icon('panel');$('#searchIcon').innerHTML=icon('search');$('#importButton').innerHTML=icon('plus')+'添加本地资料';$('#agentIcon').innerHTML=icon('chat');$('#newConversation').innerHTML=icon('plus');$('#agentLayoutButton').innerHTML=icon('panel');$('#agentPopoutButton').innerHTML=icon('external');$('#agentCloseButton').innerHTML=icon('close');$('#attachButton').innerHTML=icon('clip');$('#micButton').innerHTML=icon('mic');$('#sendButton').innerHTML=icon('send');
  state.cards.forEach(card=>{if(card.agentSource&&!sourceById(card.agentSource.id))sources.push(card.agentSource);});
  if(popout){document.body.classList.add('popout-mode',popout==='agent'?'agent-popout':'view-popout');state.groups=[{tabs:[params.get('view')||'cards'],active:params.get('view')||'cards'}];state.dock=popout==='agent'?'right':'hidden';}
  else if(innerWidth<=700&&state.mode==='library'&&state.dock!=='center')state.dock='hidden';
  $('#modal').addEventListener('click',event=>{if(event.target===$('#modal'))$('#modal').close();});
  applyTheme();renderModel();renderMessages();renderWorkspace();
  if(!popout&&!state.home)$('#startupModal').showModal();
})();
