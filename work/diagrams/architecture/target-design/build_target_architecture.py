#!/usr/bin/env python3
"""Native editable target architecture: one overview plus four whole-system views."""
from pathlib import Path
import copy
import html
import json
import xml.etree.ElementTree as E

OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[3]
W,H=2400,1700
FONT='Noto Sans CJK SC'
COLORS={'blue':('#EDF4FC','#507BA6'),'teal':('#EAF5F2','#438A7D'),'core':('#F0EFF8','#847AA8'),'data':('#F2F5F8','#8094A5'),'orange':('#FFF5E8','#C58B49'),'external':('#FAEFF1','#B67E8A'),'plain':('#F8FAFC','#CBD5DF')}
PAGES=[]
INDEX=[]
SOURCES={
 'P01':('产品目标','docs/20_product/00_产品设计总览.md'),
 'P02':('总体产品范围、云端、Agent、跨端','docs/20_product/16_正式版演进与已确认范围.md'),
 'A01':('模块化单体与分层','docs/30_design/architecture/00_系统架构总览.md'),
 'A02':('模块依赖与组合根','docs/30_design/architecture/01_系统分层与模块边界.md'),
 'A03':('本地优先与跨平台','docs/30_design/architecture/03_本地优先与跨平台架构.md'),
 'S01':('身份、VMK、接收者与调度信任边界','docs/30_design/security/07_正式版密钥恢复与接收者解密设计.md'),
 'S02':('解锁、独立恢复与换钥','docs/30_design/security/10_本机安全流程与格式v3.md'),
 'S03':('快照、独立身份、完整／分层备份','docs/30_design/security/11_本机交接与分层备份格式.md'),
 'D01':('统一信息卡片与秘密字段','docs/30_design/domain/02_账户资产关系与秘密模型.md'),
 'D02':('信息释放与可见范围','docs/30_design/domain/04_信息释放与交接策略模型.md'),
 'R01':('来源链','docs/30_design/provenance/00_来源追踪体系总览.md'),
 'R02':('修订、冲突与当前状态','docs/30_design/provenance/02_版本冲突与当前状态.md'),
 'I01':('AI隐私与授权','docs/30_design/ai/00_AI隐私处理总览.md'),
 'T01':('技术选型','docs/30_design/platform/00_应用实现架构总览.md'),
}
for _,path in SOURCES.values(): assert (ROOT/path).is_file(),path

def esc(s): return html.escape(str(s))
def rich(title,body='',size=26,body_size=22):
    return f'<div style="font-size:{size}px;font-weight:bold;line-height:1.25">{esc(title)}</div>'+ (f'<div style="font-size:{body_size}px;line-height:1.45;margin-top:6px">{esc(body).replace(chr(10),"<br/>")}</div>' if body else '')

class Page:
    def __init__(self,num,slug,title,subtitle):
        self.num,self.slug,self.title=num,slug,title
        self.d=E.Element('diagram',id=f'target-{num}',name=f'{num:02d} {title}')
        m=E.SubElement(self.d,'mxGraphModel',dx=str(W),dy=str(H),grid='1',gridSize='10',page='1',pageScale='1',pageWidth=str(W),pageHeight=str(H),background='#FFFFFF',math='0',shadow='0')
        self.r=E.SubElement(m,'root')
        E.SubElement(self.r,'mxCell',id='0'); E.SubElement(self.r,'mxCell',id='1',parent='0')
        self.cells=[]; self.boxes={}
        self.box('canvas','',0,0,W,H,'fillColor=#FFFFFF;strokeColor=none;locked=1;',decor=True)
        self.box('accent','',0,0,16,H,'fillColor=#173E61;strokeColor=none;locked=1;',decor=True)
        self.text('brand','LiveRelay  /  人生信息连续性与交接系统',55,28,2000,35,20,'#5F768B')
        self.text('title',title,55,73,2160,64,42,'#173E61',bold=True)
        self.text('subtitle',subtitle,55,145,2190,40,22,'#5F768B')
        self.box('num',f'{num:02d} / 05',2180,72,165,64,'rounded=1;arcSize=12;fillColor=#173E61;strokeColor=none;fontColor=#FFFFFF;fontSize=26;fontStyle=1;',decor=True)
        self.box('footerline','',55,1597,2290,2,'fillColor=#D2DCE5;strokeColor=none;',decor=True)
        self.text('legend','图例：蓝色实线 → 调用／数据流　 橙色实线 → 授权／投递控制　 灰色虚线 → 依赖　 虚线框 → 应用／信任边界',55,1611,2290,30,19,'#60768B')
        self.text('version','总体目标设计 v1.0  |  2026-10-04  |  本地优先 · 原始资料优先 · 默认本人可见 · 授权范围解密 · 长期可恢复',55,1651,2290,30,19,'#60768B')
        PAGES.append(self)
    def uid(self,id): return f't{self.num:02d}-{id}'
    def box(self,id,val,x,y,w,h,style='',refs=(),decor=False):
        a=dict(id=self.uid(id),value=val,vertex='1',parent='1',style=f'html=1;whiteSpace=wrap;fontFamily={FONT};fontSize=22;fontColor=#29445B;spacing=16;{style}')
        if refs: a['evidence']=','.join(refs)
        c=E.SubElement(self.r,'mxCell',**a)
        E.SubElement(c,'mxGeometry',x=str(x),y=str(y),width=str(w),height=str(h),**{'as':'geometry'})
        self.boxes[id]=(x,y,w,h)
        if not decor: self.cells.append(dict(id=self.uid(id),text=val,refs=list(refs)))
        return id
    def text(self,id,text,x,y,w,h,size=22,color='#29445B',bold=False,refs=()):
        return self.box(id,esc(text),x,y,w,h,f'text;align=left;spacing=0;fontSize={size};fontColor={color};fontStyle={1 if bold else 0};',refs,decor=not refs)
    def node(self,id,title,body,x,y,w,h,color='blue',refs=(),size=26,body_size=22):
        fill,line=COLORS[color]
        if h<85: size,body_size=min(size,21),min(body_size,17)
        elif h<110: size,body_size=min(size,22),min(body_size,18)
        return self.box(id,rich(title,body,size,body_size),x,y,w,h,f'rounded=1;arcSize=8;fillColor={fill};strokeColor={line};strokeWidth=2;align=left;verticalAlign=middle;spacing=8;',refs)
    def group(self,id,title,x,y,w,h,color='blue',refs=()):
        fill,line=COLORS[color]
        self.box(id,'',x,y,w,h,f'rounded=1;arcSize=4;fillColor={fill};fillOpacity=32;strokeColor={line};strokeWidth=2;dashed=1;dashPattern=10 5;',refs,decor=True)
        self.text(id+'label',title,x+18,y+10,w-36,36,23,'#5F768B' if color=='plain' else line,True,refs)
    def edge(self,id,src,dst,label='',kind='flow',ports=(1,.5,0,.5),points=(),refs=(),pos=0):
        color={'flow':'#507BA6','auth':'#C58B49','dep':'#8A96A5'}[kind]
        extra='dashed=1;dashPattern=9 6;endArrow=open;' if kind=='dep' else ''
        ex,ey,ix,iy=ports
        style=f'edgeStyle=orthogonalEdgeStyle;html=1;rounded=0;strokeColor={color};strokeWidth=2;endArrow=block;endFill=1;fontFamily={FONT};fontColor={color};fontSize=20;labelBackgroundColor=#FFFFFF;exitX={ex};exitY={ey};entryX={ix};entryY={iy};exitPerimeter=1;entryPerimeter=1;{extra}'
        c=E.SubElement(self.r,'mxCell',id=self.uid(id),value=esc(label),edge='1',parent='1',source=self.uid(src),target=self.uid(dst),style=style,evidence=','.join(refs))
        g=E.SubElement(c,'mxGeometry',relative='1',x=str(pos),**{'as':'geometry'})
        if points:
            a=E.SubElement(g,'Array',**{'as':'points'})
            for x,y in points: E.SubElement(a,'mxPoint',x=str(x),y=str(y))
        self.cells.append(dict(id=self.uid(id),text=label,source=self.uid(src),target=self.uid(dst),refs=list(refs)))
    def band(self,id,title,items,x,y,w,h,color='blue',cols=None,refs=()):
        self.group(id,title,x,y,w,h,color,refs)
        cols=cols or len(items)
        rows=(len(items)+cols-1)//cols
        gap=16; pad=20; top=58
        cw=(w-2*pad-gap*(cols-1))/cols
        ch=(h-top-pad-gap*(rows-1))/rows
        for i,(name,body) in enumerate(items):
            self.node(f'{id}-{i}',name,body,x+pad+(i%cols)*(cw+gap),y+top+(i//cols)*(ch+gap),cw,ch,color,refs,size=24,body_size=20)

# 01. Full system in one drawing: layers + governance + optional services.
p=Page(1,'system-overview','LiveRelay 系统总体架构图','参与者 → 跨端交互 → 业务能力 → 领域与安全内核 → 加密数据；按需连接连续性服务与外部 AI')
p.band('actors','使用与协作角色',[
 ('所有者','日常记录 · 管理凭证 · 设置授权'),('家庭协助者','协助录入 · 提醒补全 · 任务协作'),('接收者／Executor','核对身份 · 范围查看 · 交接执行'),('服务管理者','自部署／托管配置 · 调度与密文空间')],55,205,2290,162,'plain',refs=['P01','P02','S01'])
p.group('client','本地客户端应用边界  |  Flutter 模块化单体 · 移动端／桌面端 · Owner／Recipient 隔离会话',370,410,1380,971,'blue',['A01','A03','S01'])
p.band('ui','交互呈现层',[(s,'') for s in ['记录与原件','信息卡片','密码库','交接与执行','备份与恢复','我的与设置']],395,469,1330,142,'blue',refs=['P02'])
p.band('app','业务应用层',[
 ('资料采集与识别','媒体导入 · OCR · 本地转写'),('信息组织与智能整理','卡片分类 · 人工确认 · Agent'),('密码与秘密管理','生成／录入 · 专门字段 · 历史'),('来源、检索与状态维护','来源追踪 · 修订 · 冲突解释'),
 ('身份与接收者管理','双钥身份 · 绑定 · 独立接收'),('授权与交接编排','范围预览 · 手动／条件交付'),('备份、恢复与安全更新','完整／分层 · 补齐 · 全库换钥'),('同步与连续性管理','密文同步 · 报平安 · 调度协同')],395,652,1330,271,'teal',cols=4,refs=['P02','D01','R01','S03'])
p.band('core','领域与安全内核',[
 ('人生信息／生命周期','卡片与凭据 · 生命状态'),('来源与释放策略','修订／确认 · 逐项可见范围'),('AI Privacy','Token遮蔽 · Schema校验 · 回填'),('密钥与身份安全','多因素 · 独立恢复 · 签名／HPKE')],395,964,1330,165,'core',refs=['D01','D02','R02','I01','S02','S03'])
p.band('storage','加密数据与基础设施层',[
 ('结构化资料库','SQLCipher · 卡片／秘密／策略'),('加密原始资料','AES-GCM Blob · 音视频／文件'),('身份与便携资料','独立身份库 · .lvault／.lrshare'),('平台与扩展适配','插件／FFI · Provider · 导入器')],395,1170,1330,166,'data',refs=['S03','T01','A02'])
p.group('governance','安全与治理',55,410,260,971,'orange',['S01','I01','D02'])
for i,(title,body) in enumerate([
 ('身份与权限','本人默认可见\n协助与查看分离\n逐次明确授权'),('密钥所有权','VMK只属Owner\n恢复材料离线保管\nRecipient自有私钥'),('隐私与边界','外发范围可预览\nToken Map留本机\nSecret默认遮挡'),('可信与审计','原件／来源／修订\n人工确认与推断分离\n操作审计与最少遥测')]):
    p.node('govern'+str(i),title,body,75,474+i*213,220,186,'orange',['S01','I01','R01'],size=24,body_size=20)
p.group('external','可选云端与外部服务边界',1850,410,495,971,'external',['P02','S01'])
p.node('ai','外部 AI／Agent 服务','HTTPS／JSON · Provider适配\n仅接收本次预览获准的文本\n敏感行以Token替换；原件留本机',1875,474,445,205,'external',['I01','P02'],size=26,body_size=21)
p.group('continuity','连续性服务  |  自部署／托管',1875,741,445,466,'teal',['P02','S01'])
for i,(title,body) in enumerate([
 ('加密备份与密文同步','数据库／附件分层 · 版本与清单'),('摇篮调度与通知','报平安 → 提醒 → 宽限 → 预授权投递'),('接收者加密信封','保存与转递快照密文 · 按条件调度')]):
    p.node('cloud'+str(i),title,body,1895,799+i*125,405,103,'teal',['P02','S01'],size=24,body_size=20)
p.node('cloudRule','云端信任边界','服务端不持有Owner VMK或恢复凭证\n调度负责投递；接收者用自有私钥解密\n无响应不直接认定失能或身故',1875,1220,445,140,'orange',['P02','S01'],size=23,body_size=19)
p.edge('rolesToUI','actors','ui','跨端交互',ports=(.44,1,.5,0),refs=['P02'])
p.edge('uiToApp','ui','app','用例调用',ports=(.5,1,.5,0),refs=['A02'])
p.edge('appToCore','app','core','规则与安全约束',ports=(.5,1,.5,0),refs=['A02'])
p.edge('coreToData','core','storage','仓储／平台端口',ports=(.5,1,.5,0),refs=['A02'])
p.edge('externalAI','app','ai','HTTPS',ports=(1,.17,0,.7),points=[(1788,698),(1788,617)],refs=['I01'])
p.edge('externalCloud','app','continuity','HTTPS',ports=(1,.79,0,.4),points=[(1810,866),(1810,927)],refs=['P02'])
p.edge('deliverEnvelope','cloud2','actors-2','预授权密文投递',kind='auth',ports=(1,.5,.88,1),points=[(2370,1100),(2370,385),(1690,385)],refs=['S01','P02'],pos=.68)
p.band('quality','质量目标与持续演进',[
 ('可用性','核心离线可用 · 云能力按需启用'),('可靠性','认证备份 · 中断恢复 · 一致快照'),('性能','资源预算 · 后台隔离 · 附件按需读取'),('可维护与扩展','分层端口 · 适配器替换 · 格式演进'),('长期使用','跨端体验 · 无障碍 · 导入导出')],55,1420,2290,148,'plain',refs=['A03','P02','S01'])

# 02. Business capabilities: horizontal lifecycle, vertical business support.
p=Page(2,'business','LiveRelay 业务架构图','业务目标、角色、场景、价值链与领域能力：生前持续积累，风险时补全，交接时按范围使用')
p.node('value','业务目标','保持人生信息长期可用、可追溯、可恢复；在本人授权范围内支持家庭持续运转与有序交接。',55,205,2290,112,'teal',['P01'])
p.band('scenes','业务场景',[
 ('日常生活管理','账户密码 · 资料位置 · 资产／负债线索'),('风险与资料补全','关键联系人 · 家庭操作 · 定期核对'),('临时失能协助','家庭维持所需资料 · 限定范围接收'),('身故后有序交接','指定接收者 · 执行步骤 · 来源调查')],55,358,2290,176,'blue',refs=['P01','D02'])
names=['采集记录','整理确认','维护使用','持续保全','授权交付','接收执行']
bodies=['文字／照片／语音／文件\n保存原件与来源','人工／AI整理\n识别类型、核对事实','检索、修订、提醒\n维护当前状态','备份、恢复、换钥\n同步与报平安','核对身份与具体范围\n手动或预授权条件交付','独立解密、按范围查看\n任务处理、补充说明']
p.group('valueChain','业务价值链（从创建到使用与交接）',55,592,2290,232,'teal',['P01','P02'])
for i in range(6):
    p.node('stage'+str(i),f'{i+1}  {names[i]}',bodies[i],80+i*377,653,335,143,'teal',['P01','P02'],size=26,body_size=21)
    if i: p.edge('stageFlow'+str(i),'stage'+str(i-1),'stage'+str(i),'',refs=['P01'])
p.band('capabilities','业务能力',[
 ('记录与整理','快速记录 · 媒体采集 · 本地识别'),('信息与密码管理','通用卡片 · 密码专门字段 · 关联'),('资料可信维护','原件回看 · 修订历史 · 来源解释'),('安全与保全','身份／解锁 · 冷备份 · 独立恢复'),('交接与协作','接收者绑定 · 范围策略 · 执行视图'),('连续性保障','定期报平安 · 提醒／宽限 · 信封投递')],55,884,2290,217,'blue',refs=['P02','D01','R01','S03'])
p.band('domain','核心业务对象',[(s,b) for s,b in [
 ('信息卡片／凭据','记录 · 账号 · Secret'),('原件／来源／修订','证据链 · 变更 · 确认'),('身份／关系／接收者','本人 · 协助者 · 指定接收者'),('生命状态／释放策略','状态 + 条件 + 对象 → 可见级别'),('备份／授权快照','Owner恢复包 · Recipient资料包')]],55,1161,2290,189,'core',refs=['D01','D02','R01','S03'])
p.band('principles','业务治理与协作边界',[
 ('本人控制','默认本人可见；授权可定位到字段／历史／原件'),('家庭协助','协助录入不自动获得秘密或全部资料'),('信息可信','AI负责整理；事实来自原件、来源和本人确认'),('连续性条件','无响应进入提醒与宽限；按明确预授权流程交付')],55,1400,2290,167,'orange',refs=['P02','S01','I01'])
p.edge('scenarioSupport','scenes','valueChain','场景驱动',kind='dep',ports=(.5,1,.5,0),refs=['P01'])
p.edge('capSupport','valueChain','capabilities','能力支撑',kind='dep',ports=(.5,1,.5,0),refs=['P01'])
p.edge('domainSupport','capabilities','domain','领域承载',kind='dep',ports=(.5,1,.5,0),refs=['D01','D02'])

# 03. Application responsibilities, interfaces and independent execution domains.
p=Page(3,'application','LiveRelay 应用架构图','客户端模块化单体 + 可选连续性服务；应用职责、内部端口、外部接口与身份隔离')
p.group('client','本地客户端应用  |  同一Flutter package内的逻辑模块',55,205,1580,1110,'blue',['A01','A02'])
p.band('presentation','表现层',[
 ('Owner工作台','记录／卡片／密码库／交接／我的'),('Recipient入口','独立身份会话 · 范围快照与执行'),('可替换呈现','跨端布局 · 主题／档案浏览 · 无障碍')],80,272,1530,164,'blue',refs=['P02','S01'])
p.band('application','应用服务与用例编排',[
 ('资料与信息用例','采集／组织 · 检索／状态'),('智能整理用例','OCR／语音 · Agent · 人工核对'),('身份与交接用例','身份绑定 · 授权快照 · 接收'),('Vault安全用例','会话 · 策略 · 恢复 · 换钥'),('保全与连续性用例','完整／分层备份\n同步与调度协同')],80,487,1530,196,'teal',refs=['P02','A02','S03'])
p.band('domain','领域与必需安全内核',[
 ('Life Core／Provenance','信息、状态、修订、来源与策略'),('AI Privacy／授权','选择范围 · Token · 校验／回填'),('Vault／Crypto／Identity','密钥生命周期 · 身份 · 快照加密')],80,735,1530,169,'core',refs=['A02','R01','I01','S01'])
p.band('ports','内部端口与具体适配器',[
 ('仓储／原件／归档','SQLCipher · Blob · 备份文件事务'),('识别／智能／导入','OCR · Speech · AI Provider · CSV'),('平台／服务／呈现','设备因素 · 安全配置 · 备份目标 · UI')],80,956,1530,184,'data',refs=['A02','T01'])
p.node('composition','集中组合根与模块装配','入口解析平台能力与目录；集中选择实现并注入应用服务。领域规则不依赖Widget，UI／供应商不获得VMK。',80,1174,1530,110,'plain',['A02'],size=22,body_size=19)
p.group('services','可选连续性应用服务',1735,205,610,597,'teal',['P02'])
p.node('cipherStore','加密备份／同步服务','密文快照与分层附件\n认证清单 · 版本元数据 · 幂等传输',1760,275,560,141,'teal',['P02','S01'])
p.node('scheduler','摇篮与投递编排服务','报平安／提醒／宽限／条件调度\n预授权信封队列 · 通知与交接投递',1760,457,560,151,'teal',['P02','S01'])
p.node('serviceInterface','服务接口与运行支撑','HTTPS／JSON · 请求认证 · 配额与审计\n托管与Python／Docker自部署使用一致接口',1760,649,560,125,'data',['P02'])
p.group('integrations','外部服务与扩展入口',1735,854,610,406,'external',['P02'])
p.node('externalAI','模型与Agent适配','Chat Completions／Responses\n外部Agent／CLI／MCP · 明确工具授权',1760,919,560,134,'external',['P02','I01'])
p.node('externalStorage','备份与通知适配','本地文件／WebDAV／对象存储\n邮件与通知通道 · 密文包投递',1760,1096,560,134,'external',['P02'])
p.edge('presentApp','presentation','application','用例调用',ports=(.5,1,.5,0),refs=['A02'])
p.edge('appDomain','application','domain','依赖领域',kind='dep',ports=(.5,1,.5,0),refs=['A02'])
p.edge('infraDomain','ports','domain','实现核心端口',kind='dep',ports=(.5,0,.5,1),refs=['A02'])
p.edge('connectServices','application','services','HTTPS',ports=(1,.5,0,.4),refs=['P02'])
p.edge('connectAI','ports','externalAI','端口调用',ports=(1,.28,0,.5),refs=['I01','P02'])
p.band('isolation','会话与信任隔离',[
 ('Owner域','VMK／运行仓储 · 全量资料控制'),('Recipient域','自有私钥／目录 · 仅获授权快照'),('AI域','获准文本／Token · 与仓储和密钥隔离'),('连续性服务域','密文包／调度元数据 · 与Owner密钥隔离')],55,1355,2290,200,'orange',refs=['S01','S03','I01'])

# 04. Logical data architecture: lifecycle, objects, storage, exchange and keys.
p=Page(4,'data','LiveRelay 数据架构图','数据从采集、派生、确认到保全与授权消费；原始资料、结构化内容、秘密和密钥保持清晰归属')
p.band('sources','数据来源',[
 ('本人录入／家庭协助','文字 · 账号 · 状态 · 说明'),('原始媒体与文件','照片 · 音频 · 视频 · 文档'),('导入与派生内容','CSV · OCR／转写 · 获授权AI建议'),('协作与交接补充','接收任务 · 后续补充 · 来源说明')],55,205,2290,177,'blue',refs=['P02','R01'])
p.band('processing','本地处理与可信形成',[
 ('原件保全','先加密保存 · 元数据与哈希'),('内容派生','识别／解析 · 变化链可追溯'),('隐私处理','敏感标记 · Token · 外发预览'),('结构与事实核对','Schema／Token校验 · 本机回填 · 人工确认'),('版本与检索','修订／冲突并存 · 当前状态投影')],55,443,2290,191,'teal',refs=['R01','R02','I01'])
p.group('objects','逻辑数据对象（关系不自动扩大可见范围）',55,695,2290,382,'core',['D01','D02','R01'])
p.node('card','InformationCard 信息卡片','共同标识、标题、标签、时间与版本\n通用记录／凭据子类型；同一对象多种视图',85,770,640,154,'core',['D01'])
p.node('revision','Revision／Current State','追加修订 · 确认时间 · 冲突说明\n事实、个人说明与AI推断标明来源',875,770,640,154,'core',['R02'])
p.node('source','Source／Original','来源与转换链 · 原件关联\n原始名／媒体类型／哈希／来源时间',1665,770,650,154,'core',['R01'])
p.edge('revisions','card','revision','产生修订',refs=['R02'])
p.edge('provenance','revision','source','追溯来源',refs=['R01'])
p.node('secret','Credential／Secret','秘密在专门字段；普通摘要不包含Secret',85,976,640,90,'orange',['D01'],size=24,body_size=20)
p.node('policy','Identity／ReleasePolicy','对象 + 接收者 + 状态 + 条件 → 可见范围',875,976,640,90,'orange',['D02'],size=24,body_size=20)
p.node('archive','Backup／Snapshot／Receipt','恢复快照 · 授权快照 · 清单／接收记录',1665,976,650,90,'orange',['S03'],size=24,body_size=20)
p.band('storage','存储与密钥归属',[
 ('Owner SQLCipher主库','卡片／Secret／修订／策略／身份状态\n本地VMK保护；主副本在本人设备'),('AES-GCM原件存储','加密Blob；逻辑ID关联元数据\n原件与DB通过认证清单保持一致'),('Recipient独立身份与包','自有密码保护私钥与信任状态\n仅解密本次获授权资料集合'),('可选云端密文空间','加密备份／附件／同步版本\n预授权接收者信封与调度元数据')],55,1135,2290,211,'data',refs=['S01','S03','A03'])
p.band('exchange','数据保全与授权消费',[
 ('Owner恢复／同步','完整或DB＋附件配对备份\n受限重设 · 换钥 · 补齐原件'),('Recipient接收／执行','按字段、历史和原件范围生成快照\nHPKE封装／签名；自有私钥查看'),('AI整理边界','只发送所选、标记后的获准文本\nToken Map、VMK和原件保留本机')],55,1382,2290,184,'teal',refs=['S03','I01'])
p.edge('ingest','sources','processing','数据处理',ports=(.5,1,.5,0),refs=['R01'])
p.edge('confirm','processing','objects','确认后形成业务对象',ports=(.5,1,.5,0),refs=['R01'])
p.edge('store','objects','storage','按密钥归属加密持久化',ports=(.5,1,.5,0),refs=['S01'])
p.edge('consume','storage','exchange','认证与授权后使用',ports=(.5,1,.5,0),refs=['S03'])

# 05. Technology and protocols, using project choices without deployment status.
p=Page(5,'technology','LiveRelay 技术架构图','技术分层、运行环境、服务协议与工程治理；核心能力本地执行，云服务按需接入')
p.band('clientRuntime','终端与呈现技术',[
 ('移动端／桌面端','Android · Linux · Windows\n共享业务与跨端布局'),('Flutter／Dart','Material 3 · 主题令牌 · 状态投影\n可访问性 · 可替换档案呈现'),('平台插件与FFI','媒体采集／回放 · 文件与目录\nMethodChannel · Native／FFI')],55,205,1620,185,'blue',refs=['P02','T01'])
p.band('applicationRuntime','应用执行与集成',[
 ('分层与依赖注入','Presentation → Application → Core\n组合根 · 内部端口 · 具体适配器'),('本地OCR／语音','ML Kit／OCR Provider\nSenseVoice · sherpa_onnx · CPU'),('受控Agent运行','Responses／Chat Completions适配\n工具授权 · OS隔离 · 资源限制')],55,452,1620,204,'teal',refs=['A02','T01','P02'])
p.band('security','身份、隐私与密码技术',[
 ('凭证与设备因素','Argon2id · HKDF · 任一／全部分支\n平台密钥存储 · 强生物识别'),('资料加密与授权包','SQLCipher · AES-256-GCM\nX25519／HPKE · Ed25519签名'),('隐私与密钥生命周期','Tokenization · Schema校验／回填\n独立恢复 → 受限重设 → 全库换钥')],55,718,1620,207,'core',refs=['T01','S02','S03','I01'])
p.band('persistence','持久化与交换技术',[
 ('结构化数据库','Drift／Repository · SQLCipher\n版本迁移 · 事务 · 本地索引'),('文件与归档','AES-GCM Blob · 认证清单\n.lvault／.lridentity／.lrshare'),('恢复与版本保全','staging／rollback／commit\n配对snapshotId · 逐项补齐')],55,987,1620,213,'data',refs=['T01','S03','S02'])
p.group('cloudRuntime','云端／自部署运行环境',1770,205,575,995,'external',['P02'])
p.node('server','Python应用／Docker部署','备份与密文同步 · 摇篮／投递调度\n托管服务与自部署采用一致接口',1795,275,525,180,'external',['P02'])
p.node('protocol','接口与通信协议','HTTPS／TLS · JSON服务接口\nAI：Responses／Chat Completions\n存储：WebDAV／文件与对象存储\n通知：邮件／通知服务适配',1795,513,525,230,'external',['P02','T01'])
p.node('infra','云端基础设施','加密对象／附件存储\n调度队列、作业执行与通知通道\n请求认证、限额与安全审计',1795,802,525,174,'data',['P02'])
p.node('trust','服务与端侧密钥隔离','服务侧保存密文与最少调度信息\nOwner VMK／恢复材料保留在本人侧\nRecipient私钥属于接收者身份',1795,1033,525,141,'orange',['S01'],size=24,body_size=20)
p.edge('runtimeUse','clientRuntime','applicationRuntime','调用',ports=(.5,1,.5,0),refs=['A02'])
p.edge('applicationSecurity','applicationRuntime','security','规则与安全接口',ports=(.5,1,.5,0),refs=['A02'])
p.edge('securityStore','security','persistence','加密仓储／文件端口',ports=(.5,1,.5,0),refs=['A02'])
p.edge('clientCloud','applicationRuntime','protocol','HTTPS',ports=(1,.5,0,.3),refs=['P02'])
p.band('engineering','工程治理与非功能设计',[
 ('可靠与可恢复','认证清单 · 一致快照 · 有界输入\n中断保留可认证副本 · 明确失败'),('性能与资源','后台isolate · CPU／内存预算\n附件按需访问 · 大文件加密演进'),('可维护与可扩展','端口替换 · 模块边界 · 格式版本\n跨端适配 · 可迁移数据格式'),('安全与长期使用','密钥生命周期 · 最少遥测 · 日志脱敏\n依赖治理 · 无障碍 · 开源可持续')],55,1262,2290,275,'plain',refs=['P02','A03','S01','T01'])

def mxfile(pages):
    m=E.Element('mxfile',host='Electron',agent='LiveRelay target-design generator',version='30.2.4',compressed='false')
    for p in pages: m.append(copy.deepcopy(p.d))
    E.indent(m,space='  ')
    return m

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    E.ElementTree(mxfile(PAGES)).write(OUT/'LiveRelay-总体目标架构.drawio',encoding='utf-8',xml_declaration=True)
    single=mxfile(PAGES[:1])
    single.find(".//mxCell[@id='t01-num']").set('value','单张总图')
    E.ElementTree(single).write(OUT/'LiveRelay-系统总体架构.drawio',encoding='utf-8',xml_declaration=True)
    stats=[]
    for p in PAGES:
        ids={c.get('id') for c in p.r}
        for id,(x,y,w,h) in p.boxes.items(): assert min(x,y,w,h)>=0 and x+w<=W and y+h<=H,(p.num,id)
        for c in p.r:
            if c.get('source'): assert c.get('source') in ids
            if c.get('target'): assert c.get('target') in ids
        for c in p.cells:
            for ref in c['refs']: assert ref in SOURCES,ref
        stats.append(dict(page=p.num,title=p.title,slug=p.slug,vertices=len(p.boxes),edges=sum(c.get('edge')=='1' for c in p.r),cells=p.cells))
    data=dict(date='2026-10-04',version='1.0',purpose='总体目标设计',canvas=[W,H],sources={k:dict(title=t,path=path) for k,(t,path) in SOURCES.items()},reference='https://blog.csdn.net/kunwen123/article/details/122854209',pages=stats)
    (OUT/'design-index.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(dict(pages=5,singleOverviewPages=1,vertices=sum(p['vertices'] for p in stats),edges=sum(p['edges'] for p in stats)),ensure_ascii=False))

if __name__=='__main__': main()
