#!/usr/bin/env python3
"""Generate editable, uncompressed mxGraph pages and a source evidence index.

No application code or user data is read. Source anchors are checked on rebuild.
Exports are produced by the installed draw.io CLI; see README.md.
"""
from pathlib import Path
import json
import html
import xml.etree.ElementTree as ET

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
LIB = 'work/code/live_relay/lib/'
W, H = 1800, 1120
FONT = 'Noto Sans CJK SC'
SOURCES = {}

def source(key, name, path, anchor, end=None):
    lines = (ROOT / path).read_text().splitlines()
    start = next(i + 1 for i, line in enumerate(lines) if anchor in line)
    stop = start if end is None else next(i + 1 for i, line in enumerate(lines[start-1:], start-1) if end in line)
    SOURCES[key] = dict(title=name, path=path, line=start, endLine=stop, anchor=anchor)

source('D01', '当前系统架构', 'docs/30_design/architecture/00_系统架构总览.md', '## 当前结论')
source('D02', '分层与内部端口', 'docs/30_design/architecture/01_系统分层与模块边界.md', '## MVP 实际分层')
source('D03', '平台实现与验收边界', 'docs/30_design/platform/00_应用实现架构总览.md', '## MVP 技术基线')
source('D04', 'Header v3／恢复／换钥规格', 'docs/30_design/security/10_本机安全流程与格式v3.md', '独立 Header v3 suite')
source('D05', '身份／范围／分层备份规格', 'docs/30_design/security/11_本机交接与分层备份格式.md', '## 独立身份与信任')
source('D06', '10月4日实际联调', 'docs/60_quality/2026-10-04_实际联调验证.md', '## 已验证')
source('D07', '已确认的后续方向', 'docs/20_product/16_正式版演进与已确认范围.md', '## 摇篮服务、备份与服务器')
source('D08', 'Agent密码录入已知缺口', 'docs/60_quality/2026-10-04_实际联调验证.md', '## Agent账号密码卡片录入缺口')
source('C01', '集中组合根', LIB+'infrastructure/app_composition.dart', 'AppController createAppController(')
source('C02', 'Controller初始化与启动恢复', LIB+'application/app_controller.dart', 'Future<void> initialize()')
source('C03', '会话密钥临时副本', LIB+'application/vault_session.dart', 'Future<T> withMasterKey<T>')
source('C04', '受限恢复会话', LIB+'application/vault_session.dart', 'Future<void> unlockWithRecovery')
source('C05', '全库换钥与提交', LIB+'application/vault_security_service.dart', 'Future<void> configure(')
source('C06', '备份认证与恢复', LIB+'application/vault_backup_service.dart', 'Future<void> restore(')
source('C07', '配对导出与补充恢复', LIB+'application/vault_backup_service.dart', 'Future<({Uint8List database, Uint8List attachments})> exportSplit(')
source('C08', '恢复目录安装事务', LIB+'infrastructure/backup/vault_restore_transaction.dart', 'Future<String?> install(')
source('C09', '启动中断恢复', LIB+'infrastructure/backup/vault_restore_transaction.dart', 'Future<String?> _recover(')
source('C10', 'Owner挑战与限定快照', LIB+'application/local_handoff_service.dart', 'Future<Uint8List> createChallenge(')
source('C11', '限定范围导出', LIB+'application/local_handoff_service.dart', 'Future<Uint8List> exportScope(')
source('C12', 'Recipient独立接收验证', LIB+'application/recipient_service.dart', 'Future<void> receive(')
source('C13', 'Recipient独立密码身份', LIB+'application/recipient_service.dart', 'Future<void> unlock(String password)')
source('C14', '身份指纹与双钥', LIB+'core/identity/local_identity.dart', 'class LocalIdentity')
source('C15', 'HPKE实现', LIB+'core/identity/hpke.dart', 'class LocalHpke')
source('C16', 'Agent单次授权UI', LIB+'presentation/pages/agent_page.dart', 'Future<void> _runAgent()')
source('C17', 'Agent Tokenization与请求', LIB+'application/draft_agent_service.dart', 'class DraftAgentService')
source('C18', 'Token校验与本机回填', LIB+'core/ai/ai_privacy.dart', 'class AiPrivacyProcessor')
source('C19', 'Agent结果保存', LIB+'application/app_controller.dart', 'Future<void> saveAgentDrafts(')
source('C20', 'Linux命令隔离', LIB+'infrastructure/agent/linux_bash_command_provider.dart', 'Future<AgentCommandSession> open(')
source('C21', '本地转写与isolate', LIB+'infrastructure/speech/local_sense_voice_provider.dart', 'Future<String> transcribe(')
source('C22', '语音来源草稿', LIB+'application/app_controller.dart', 'Future<void> saveSpeechDraft(')
source('C23', '数据库实体映射', LIB+'infrastructure/persistence/app_database.dart', 'class Sources extends Table')
source('C24', 'SQLCipher打开／schema v5', LIB+'infrastructure/persistence/app_database.dart', 'static Future<AppDatabase> openEncrypted(')
source('C25', '原件AES-GCM／换钥', LIB+'infrastructure/blob/encrypted_blob_store.dart', 'class EncryptedBlobStore')
source('C26', '采集与OCR应用用例', LIB+'application/app_controller.dart', 'Future<LifeCard> runOcr(')
source('C27', 'Provider配置的系统安全存储', LIB+'infrastructure/ai/ai_provider_settings_store.dart', 'class AiProviderSettingsStore')
source('C28', '纯领域生命状态规则', LIB+'core/domain/lifecycle.dart', 'class LifeStateMachine')
source('C29', '接收入口先锁Owner', LIB+'presentation/pages/recipient_page.dart', 'if (controller.isUnlocked) await controller.lock();')
source('C30', 'Header任一／全部密码学', LIB+'core/security/vault_header_v3.dart', 'class VaultHeaderV3')
source('C31', '设备因素MethodChannel', LIB+'infrastructure/security/android_device_factor_protection.dart', 'class AndroidDeviceFactorProtection')
source('C32', 'Android Keystore强生物识别', 'work/code/live_relay/android/app/src/main/kotlin/app/liverelay/live_relay/DeviceFactorChannel.kt', 'class DeviceFactorChannel')
source('C33', '正常入口', LIB+'main.dart', 'Future<void> main()')
source('C34', '虚构演示入口', LIB+'main_debug_demo.dart', 'Future<void> main()')
source('C35', 'Responses工具循环', LIB+'infrastructure/ai/responses_agent_provider.dart', 'class ResponsesAgentProvider')
source('C36', '数据来源查询', LIB+'infrastructure/persistence/sqlite_vault_repository.dart', 'Future<List<CardSource>> cardSources(')

THEMES = {
 'app': ('#EAF5F4','#287E77'),
 'core': ('#EEF1FA','#6577A2'),
 'store': ('#F1F4F8','#79899E'),
 'person': ('#F5F0E9','#A7865B'),
 'control': ('#FFF4E3','#D18A32'),
 'external': ('#FBEFF0','#BC757E'),
 'plan': ('#F6F6F7','#ADB3BE'),
 'note': ('#F7F9FB','#D8E0E8'),
}
EDGE = {'flow':('#287E77',''), 'dependency':('#7C8799','dashed=1;dashPattern=8 5;endArrow=open;'), 'inject':('#8761A9','dashed=1;dashPattern=2 4;'), 'auth':('#CD832A','')}

mxfile = ET.Element('mxfile', host='Electron', agent='LiveRelay architecture builder / draw.io 30.2.4', version='30.2.4', modified='2026-10-04T00:00:00.000Z', compressed='false')
PAGES = []

def esc(x): return html.escape(str(x))

class Page:
    def __init__(self, number, slug, title, subtitle):
        self.n, self.slug, self.title = number, slug, title
        diagram = ET.SubElement(mxfile,'diagram', id=f'lr-{number:02d}', name=f'{number:02d} {title}')
        model = ET.SubElement(diagram,'mxGraphModel', dx=str(W),dy=str(H), grid='1',gridSize='10',guides='1',tooltips='1',connect='1',arrows='1',fold='1',page='1',pageScale='1',pageWidth=str(W),pageHeight=str(H),math='0',shadow='0',background='#FFFFFF')
        self.root = ET.SubElement(model,'root')
        ET.SubElement(self.root,'mxCell',id='0')
        ET.SubElement(self.root,'mxCell',id='1',parent='0')
        self.items, self.geoms, self.routes = [], {}, []
        self.rect('canvas','',0,0,W,H, 'fillColor=#FFFFFF;strokeColor=none;locked=1;', kind='decor')
        self.rect('stripe','',0,0,14,H,'fillColor=#287E77;strokeColor=none;locked=1;',kind='decor')
        self.text('brand','L I V E R E L A Y  /  ARCHITECTURE REVIEW',50,28,1450,26,15,'#617284')
        self.text('title',title,50,60,1560,52,34,'#163A43',bold=True)
        self.text('subtitle',subtitle,50,117,1660,34,18,'#617284')
        self.rect('pageNo',f'{number:02d} / 11',1600,52,148,48,'rounded=1;arcSize=18;fillColor=#163A43;strokeColor=none;fontColor=#FFFFFF;fontSize=22;fontStyle=1;',kind='decor')
        self.rect('footerLine','',50,1014,1698,2,'fillColor=#D7E1E7;strokeColor=none;',kind='decor')
        self.text('legend','箭头：实线绿 = 调用／数据流　 虚线灰 = 代码依赖　 点线紫 = 组合注入　 实线橙 = 本人授权／凭证',50,1025,1690,27,16,'#617284')
        self.text('status','状态：[实现] 已有代码　 [现场] 代表链路已验证　 [待验] 其余平台／安全验收　 [规划] 尚未实现　 端口／格式均为内部未冻结',50,1055,1690,25,15,'#617284')
        self.text('version','MVP0.4 · 1.0.0+3  |  源码 6fbee32  |  文档 a586349  |  2026-10-04  |  图版 v1.0  |  单 Flutter package · Local-first',50,1082,1690,25,15,'#617284')
        PAGES.append(self)
    def uid(self, id): return f'p{self.n:02d}-{id}'
    def rect(self,id,value,x,y,w,h,style='',refs=(),kind='node'):
        attrs=dict(id=self.uid(id),value=value,style=f'html=1;whiteSpace=wrap;fontFamily={FONT};fontSize=19;fontColor=#263D4B;spacing=14;{style}',vertex='1',parent='1')
        if refs: attrs['evidence']=','.join(refs)
        cell=ET.SubElement(self.root,'mxCell',**attrs)
        ET.SubElement(cell,'mxGeometry',x=str(x),y=str(y),width=str(w),height=str(h),**{'as':'geometry'})
        self.geoms[id]=(x,y,w,h)
        if kind not in ('decor','group'):
            self.items.append(dict(id=self.uid(id),kind=kind,label=html.unescape(ET.fromstring('<x>'+value+'</x>').itertext().__next__()) if '<' not in value else value,refs=list(refs)))
        return id
    def text(self,id,value,x,y,w,h,size=19,color='#263D4B',bold=False,refs=()):
        return self.rect(id,esc(value),x,y,w,h,f'text;align=left;verticalAlign=middle;spacing=0;fontSize={size};fontColor={color};fontStyle={1 if bold else 0};',refs,'decor' if not refs else 'note')
    def group(self,id,title,x,y,w,h,color='#D7E1E7',fill='#FAFCFD',refs=()):
        self.rect(id,'',x,y,w,h,f'rounded=1;arcSize=8;fillColor={fill};strokeColor={color};strokeWidth=2;dashed=1;dashPattern=9 5;',refs,kind='group')
        self.text(id+'Label',title,x+18,y+10,w-36,32,18,'#617284',bold=True,refs=refs)
    def node(self,id,title,body,x,y,w,h,t='app',refs=(),tag='实现',shape=''):
        fill,stroke=THEMES[t]
        txt=f'<div style="font-size:22px;font-weight:bold;line-height:1.25">{esc(title)}</div>'
        if body: txt+=f'<div style="font-size:18px;line-height:1.5;margin-top:10px">{esc(body).replace(chr(10),"<br/>")}</div>'
        if tag: txt+=f'<div style="font-size:14px;color:#667788;margin-top:8px">[{esc(tag)}]</div>'
        dashed='dashed=1;dashPattern=8 5;' if t=='plan' else ''
        st=f'rounded=1;arcSize=12;align=left;verticalAlign=middle;fillColor={fill};strokeColor={stroke};strokeWidth=2;{dashed}{shape}'
        return self.rect(id,txt,x,y,w,h,st,refs)
    def note(self,id,title,body,x,y,w,h,refs=(),t='note'):
        return self.node(id,title,body,x,y,w,h,t,refs,tag='')
    def edge(self,id,src,dst,label='',kind='flow',refs=(),ports=(1,.5,0,.5),points=(),labelpos=0):
        color,extra=EDGE[kind]
        st=f'edgeStyle=orthogonalEdgeStyle;orthogonalLoop=1;jettySize=auto;html=1;rounded=0;strokeWidth=2;endArrow=block;endFill=1;strokeColor={color};fontColor={color};fontSize=16;fontFamily={FONT};labelBackgroundColor=#FFFFFF;labelBorderColor=none;spacing=5;{extra}'
        if ports:
            ex,ey,ix,iy=ports
            st+=f'exitX={ex};exitY={ey};entryX={ix};entryY={iy};exitPerimeter=1;entryPerimeter=1;'
        a=dict(id=self.uid(id),value=esc(label),style=st,edge='1',parent='1',source=self.uid(src),target=self.uid(dst))
        if refs: a['evidence']=','.join(refs)
        cell=ET.SubElement(self.root,'mxCell',**a)
        g=ET.SubElement(cell,'mxGeometry',relative='1',x=str(labelpos),**{'as':'geometry'})
        if points:
            arr=ET.SubElement(g,'Array',**{'as':'points'})
            for x,y in points: ET.SubElement(arr,'mxPoint',x=str(x),y=str(y))
        self.items.append(dict(id=self.uid(id),kind='edge:'+kind,label=label,source=self.uid(src),target=self.uid(dst),refs=list(refs)))
    def lifeline(self,id,title,x,refs=(),t='app'):
        self.node(id,title,'',x-150,177,300,74,t,refs,tag='')
        self.rect(id+'Line','',x,254,1,595,'fillColor=#C1CED9;strokeColor=none;',kind='decor')
    def message(self,id,x1,x2,y,label,refs=(),auth=False):
        # Explicit source/target coordinates: true native editable sequence arrows.
        color=EDGE['auth' if auth else 'flow'][0]
        st=f'html=1;endArrow=block;endFill=1;strokeWidth=2;strokeColor={color};fontColor={color};fontFamily={FONT};fontSize=17;labelBackgroundColor=#FFFFFF;'
        cell=ET.SubElement(self.root,'mxCell',id=self.uid(id),value=esc(label),style=st,edge='1',parent='1',evidence=','.join(refs))
        g=ET.SubElement(cell,'mxGeometry',relative='1',**{'as':'geometry'})
        ET.SubElement(g,'mxPoint',x=str(x1),y=str(y),**{'as':'sourcePoint'})
        ET.SubElement(g,'mxPoint',x=str(x2),y=str(y),**{'as':'targetPoint'})
        ET.SubElement(g,'mxPoint',x='0',y='-13',**{'as':'offset'})
        self.items.append(dict(id=self.uid(id),kind='message',label=label,refs=list(refs)))

# 01: context
p=Page(1,'context','系统上下文与外部参与者','C4 Level 1  |  谁使用系统、与哪些外部能力交互，以及当前实现边界')
p.group('system','当前系统边界：本地优先 LiveRelay 客户端',500,290,735,375,refs=['D01'])
p.node('owner','所有者 Owner','录入、核对、保存；保管恢复材料\n逐次批准 AI 外发与指定范围交付',60,350,360,225,'person',['D01','D05'],tag='现场')
p.node('app','LiveRelay 客户端','加密资料库 · 记录／卡片／密码库\n本地语音 · 受控 Agent · 手动交接\n完整／分层备份 · 独立恢复',550,357,635,250,refs=['D01','C01'],tag='实现／现场')
p.node('recipient','独立接收者 Recipient','自有身份、密码与目录\n核对身份；只读查看获授权快照',1320,350,420,225,'person',['D05','C12'],tag='现场')
p.node('ai','本人配置的网络 AI','HTTPS · Chat Completions／Responses\n只接收获准文本；属于外部信任域',535,735,625,178,'external',['C17','C35','C27'],tag='实现／受控Provider现场')
p.node('os','操作系统／本地能力','摄像／录音／文件选择\n强生物识别、Keystore／Secret Service',60,735,385,178,'store',['D03','C31'],tag='实现／按平台')
p.node('files','本人控制的文件媒介','设备外冷备份 .lvault\n公开身份、挑战响应、.lrshare',1320,735,420,178,'store',['D05','C06','C11'])
p.edge('ownerUse','owner','app','解锁／编辑／授权','auth',['D01'],ports=(1,.5,0,.5))
p.edge('recipientUse','app','recipient','独立接收入口／快照','flow',['C29','C12'])
p.edge('useOS','app','os','平台能力','flow',['C01'],ports=(.15,1,1,0),points=[(645,690),(420,690)])
p.edge('sendAi','app','ai','单次预览后发送','auth',['C16','C17'],ports=(.5,1,.5,0))
p.edge('manualFiles','app','files','手动导出／导入','flow',['C06','C11'],ports=(.85,1,0,0),points=[(1090,690),(1320,690)])
p.note('plans','[规划] 后续外部系统','同步／WebDAV／云备份 · 摇篮通知与自动条件释放 · 外部 Agent／CLI／MCP。当前没有运行连接。',60,180,1680,74,['D07'],'plan')

# 02: logical containers
p=Page(2,'containers','应用与存储的运行边界','C4 Level 2  |  一个客户端部署单元；本地数据存储与外部进程按实际职责区分')
p.group('client','同一 Flutter package：应用进程 + 运行时工作 isolate',60,180,1035,640,refs=['D01','D03'])
p.node('ui','Material 3 表现层','记录／卡片／密码库／交接／我的\n首次使用、锁定、独立接收入口',90,245,950,145,refs=['D02','C29'])
p.node('uses','Application 用例协调','AppController 页面状态；VaultSession 会话\n安全、备份、身份、交接、Agent、语音服务',90,443,950,158,refs=['C01','D02'])
p.node('native','基础设施／原生适配','SQLCipher 数据库工作 isolate；sherpa_onnx 转写 isolate／FFI\nAndroid MethodChannel／插件；具体 Provider 与文件适配',90,645,950,150,'core',['C01','C21','C24'],tag='实现')
p.node('ownerDisk','Owner 资料目录','live_relay/vault/\nHeader + SQLCipher + 加密 Blob',1225,210,515,155,'store',['C01','C24','C25'])
p.node('recipDisk','Recipient 独立目录','live_relay/recipient/\n加密身份／信任状态 + .lrshare 密文',1225,410,515,155,'store',['C01','C12','C13'])
p.node('support','辅助本地资源','speech/：模型与安装状态\n系统安全存储：AI 配置及 API Key',1225,610,515,155,'store',['C01','C21','C27'])
p.edge('usecases','ui','uses','页面调用用例','flow',['D02'],ports=(.5,1,.5,0))
p.edge('adapters','uses','native','端口调用／实现适配','flow',['C01'],ports=(.5,1,.5,0))
p.edge('writeOwner','uses','ownerDisk','会话仓储／原件接口','flow',['C03','C24'],ports=(1,.22,0,.5),points=[(1145,478),(1145,285)])
p.edge('writeRecipient','uses','recipDisk','RecipientService','flow',['C12','C13'],ports=(1,.55,0,.5))
p.edge('readSupport','native','support','模型／安全配置','flow',['C21','C27'])
p.note('processes','另外启动的进程与服务','Linux 隔离 Bash：bubblewrap + prlimit，本次启用后只读遮蔽文本；远端 AI：HTTPS 服务。Dart isolate 是应用运行单元，均不是独立微服务。',60,850,1680,110,['C20','C17','D03'])

# 03: component and dependency
p=Page(3,'components','逻辑分层、组件、内部端口与组合根','C4 Level 3  |  箭头在本页表达代码依赖或装配；不将每个模块画成独立部署服务')
p.group('presentation','Presentation',60,180,420,150,refs=['D02'])
p.node('pages','页面与设计系统','页面交互、投影、主题和导航',85,225,370,83,refs=['D02'],tag='')
p.group('application','Application：状态与用例',60,375,420,555,refs=['D02'])
p.node('controller','AppController','忙碌／错误／投影；不持有 VMK',85,421,370,90,refs=['C01','D02'],tag='')
p.node('vaultUse','VaultSession + Security／Backup','会话、凭证重设、换钥、恢复',85,542,370,108,refs=['C03','C05','C06'],tag='')
p.node('identityUse','LocalHandoff／Recipient','独立身份、授权快照和接收',85,680,370,88,refs=['C10','C12'],tag='')
p.node('aiUse','DraftAgent／Speech','授权工具循环、本地转写',85,797,370,92,refs=['C17','C21'],tag='')
p.group('core','Core：纯领域／隐私／安全逻辑 + 内部端口',605,375,595,555,refs=['D02'])
p.node('domain','Domain／AI Privacy／Security','InformationCard、LifeState、ReleasePolicy\n来源／修订；Token 遮蔽／校验／回填\nHeader v3、身份、HPKE 密码学',635,430,535,173,'core',['C18','C28','C30','C14','C15'],tag='')
p.node('ports','core/ports 内部替换端口','VaultRepository · VaultBlobStore\nAiProvider · OcrProvider · SpeechProvider\nAgentCommandProvider · DeviceFactorProtection',635,663,535,187,'core',['C01','D02'],tag='内部未冻结')
p.group('infrastructure','Infrastructure：当前实现',1300,375,440,555,refs=['D02'])
p.node('impl','具体适配器','SqliteVaultRepository／EncryptedBlobStore\nConfiguredAiProvider／ML Kit OCR\nLocalSenseVoiceProvider／Linux Bash\nAndroidDeviceFactorProtection',1325,435,390,228,'store',['C01','C20','C21','C31'],tag='')
p.node('transactions','归档与文件事务','LifeVaultArchive／VaultRestoreTransaction\n系统安全配置、CSV、平台路径',1325,730,390,134,'store',['C06','C08','C27'],tag='')
p.node('root','main.dart → app_composition.createAppController','集中创建默认实现、解析目录、准备环境；具名注入控制器与用例服务',605,180,1135,150,'control',['C01','C33'],tag='组合根')
p.edge('presDep','pages','controller','依赖','dependency',['D02'],ports=(.5,1,.5,0))
p.edge('appDepDomain','controller','domain','依赖 Core','dependency',['D02'],ports=(1,.5,0,.3))
p.edge('appDepPorts','vaultUse','ports','调用端口','dependency',['C01','C03'],ports=(1,.5,0,.3),points=[(540,596),(540,718)])
p.edge('infraDep','impl','ports','实现端口','dependency',['C01','D02'],ports=(0,.8,1,.5),points=[(1245,618),(1245,757)])
p.edge('injectApp','root','controller','注入服务','inject',['C01'],ports=(0,.65,1,.15),points=[(550,278),(550,433)])
p.edge('buildInfra','root','impl','创建／装配','inject',['C01'],ports=(.8,1,.5,0),points=[(1515,350)])
p.text('exception','渐进分层事实：部分 Application 仍引用具体归档／错误与配置类型；并未宣称所有基础设施依赖已完全反转。',65,951,1670,38,17,'#617284',refs=['D02','C05','C06'])

# 04: deployment
p=Page(4,'deployment','部署结构与平台能力','部署视图  |  相同业务含义、不同原生能力；实现、现场验证与待验收分别记录')
p.group('android','Android 设备  |  API 24+ · target 36',60,180,795,560,refs=['D03'])
p.node('apk','Flutter APK／Dart 运行时','MVP0.4 · 内部 1.0.0+3\n小米13／Android13 代表链路已验证',90,242,735,124,refs=['D03','D06'],tag='现场')
p.node('androidNative','插件／FFI／MethodChannel','SQLCipher · sherpa_onnx\nML Kit 中文 OCR · 采集／播放插件\nKotlin CryptoObject + 强生物识别',90,420,440,244,'core',['D03','C24','C21','C32'],tag='实现／部分现场')
p.node('keystore','Android Keystore','保护设备因素份额\n每次授权后 AAD／doFinal\n平台结果复制为可写32字节',575,420,250,244,'store',['C31','C32','D04'],tag='小米13现场')
p.edge('androidRuntime','apk','androidNative','插件／FFI','flow',['D03'],ports=(.3,1,.5,0))
p.edge('factor','androidNative','keystore','份额','flow',['C31','C32'])
p.group('linux','Linux 桌面  |  x86_64 · Ubuntu22.04 构建基线',935,180,805,560,refs=['D03','D06'])
p.node('bundle','Flutter runner + bundle','SQLCipher／sherpa_onnx 动态库随包\nUbuntu22.04 启动与 EndeavourOS 现场试用',965,242,745,124,refs=['D03','D06'],tag='现场')
p.node('linuxNative','桌面插件与系统服务','GTK／音频／文件／播放\n本地短录音／WAV → 草稿／来源重开\nSecret Service：AI 配置安全存储',965,420,425,244,'core',['C21','C27','D06'],tag='现场／限定环境')
p.node('bash','可选隔离命令','bwrap + Bash + prlimit\nuser/network namespace\n只读 /input；限时／限资源',1435,420,275,244,'store',['C20'],tag='实现／Linux')
p.edge('linuxRuntime','bundle','linuxNative','本地库／插件','flow',['D03'],ports=(.3,1,.5,0))
p.edge('sandbox','bundle','bash','单次启用工具','auth',['C20','C16'],ports=(.83,1,.5,0))
p.note('pending','[待验] Windows 与发行安全','Windows runner 已准备，尚未构建／运行验收。正式签名、安全外部复核、更多指纹组合／机型／声卡／日常密钥环仍待完成。',60,795,795,175,['D03','D06'],'control')
p.note('demo','隔离调试与未来平台','main_debug_demo：独立临时目录、虚构资料、注入控制；正常入口不复用演示资料。macOS 尚无工程；云端不在当前部署中。',935,795,805,175,['C34','D03'],'note')

# 05: data and security
p=Page(5,'data-security','数据、来源、VMK 所有权与信任边界','数据／安全视图  |  明文只在解锁与受控操作期间存在；凭证、主密钥和接收者密钥分开')
p.group('credential','本人保管／平台凭证域',60,180,470,775,color='#D4AE75',fill='#FFFBF4',refs=['D04'])
p.node('daily','日常因素 → Header v3 分支','密码：Argon2id 64MiB／3／1\n可选随机文件：精确32字节\n可选设备：Keystore 保护份额',90,242,410,170,'control',['C30','D04'],tag='实现／组合待扩验')
p.node('branches','any / all 的密码学强制','any：各因素独立单因素分支\nall：n-of-n 份额 XOR 组合分支 B\nHKDF 分支钥 → 解封 VMK',90,475,410,185,'core',['C30','D04'],tag='内部格式')
p.node('recovery','离线独立恢复 R / LRR1','随机 R；独立恢复分支\n不保存到 Header／偏好／日志\n绕过日常因素，只进入受限重设',90,715,410,180,'control',['D04','C04'],tag='现场／受限')
p.edge('factors','daily','branches','解封份额','auth',['C30'],ports=(.5,1,.5,0))
p.group('owner','Owner 解锁会话与加密存储域',595,180,690,775,refs=['C03','C24','C25'])
p.node('vmk','VaultSession 持有 VMK','随机32字节；受控临时副本供安全／备份\nAppController／UI／网络 AI 不持有 VMK\n锁定时关闭仓储并清除会话密钥',625,242,630,175,refs=['C03','C05','C06','D02'],tag='实现')
p.node('db','SQLCipher schema v5','LifeCard／Credential 与各自 Revision\nSources、EncryptedBlobs 元数据、关系\nReleasePolicy／LifeState／Audit\nvault_local_state：身份私钥、绑定、缺失状态',625,485,630,218,'store',['C23','C24','C10','C07'])
p.node('blob','AES-256-GCM 原件 Blob','随机 ID 文件名；AAD 绑定 Blob ID\n原始名／哈希／OCR／标注在加密数据库\n修订 → Source → blobId；按来源回看',625,776,630,170,'store',['C25','C23','C36'])
p.edge('dailyUnlock','branches','vmk','认证 Header MAC／解封','flow',['C30'],ports=(1,.3,0,.55),points=[(563,530),(563,338)])
p.edge('recoveryUnlock','recovery','vmk','受限会话','auth',['C04'],ports=(1,.45,0,.9),points=[(558,796),(558,400)])
p.edge('dbKey','vmk','db','VMK 打开数据库','flow',['C24'],ports=(.5,1,.5,0))
p.edge('blobKey','vmk','blob','VMK 加解密原件','flow',['C25'],ports=(1,.6,1,.5),points=[(1270,348),(1270,848)])
p.edge('sourceRef','db','blob','逻辑引用／来源链','flow',['C23','C36'],ports=(.5,1,.5,0))
p.node('header','磁盘公开 Header v3','元数据 + 被封装因素／VMK槽\nDescriptor／AAD／Header HMAC\n保留 v1／v2 reader；主动升级旧库',1350,205,390,195,'store',['D04','C30'])
p.node('recipientKeys','Recipient 自有钥域','自有密码保护 .lridentity\nX25519／Ed25519 私钥与信任状态\n从不取得 Owner VMK',1350,450,390,195,'external',['C13','C14','D05'])
p.node('aiBoundary','AI 外部信任域','只见预览获准文本／敏感行Token\nToken Map 留本机；API Key 单独\n不访问库、原件、主密钥或私钥',1350,695,390,225,'external',['C17','C18','C27','D08'])

# 06: capture speech
p=Page(6,'capture-speech','采集、本地语音与来源保留','工作流视图  |  原始资料优先；转写／OCR 是派生内容，确认后作为有来源的草稿保存')
p.group('local','全部识别与来源保存步骤位于设备内',60,180,1680,720,refs=['C21','C22','C26'])
p.node('capture','本人主动采集／导入','照片／文件／录音／录像\n平台能力与权限明确显示',90,250,340,162,refs=['D03','C26'],tag='实现／按平台')
p.node('store','加密保存原件','VaultSession → VaultBlobStore\nBlob + 元数据；来源可回看',550,250,490,162,'store',['C25','C26'],tag='实现／现场')
p.node('vault','草稿／来源持久化','LifeCard 草稿 + Revision + Source\n引用原件 blobId；锁定／重开后回看',1210,250,490,162,'store',['C22','C23','C36'],tag='现场')
p.node('ocr','端侧中文 OCR','Google ML Kit／OcrProvider\n行文本 + 坐标；人工敏感标注',90,540,390,200,'core',['C26','D03'],tag='实现／Android')
p.node('speech','本地语音转写','SpeechService → LocalSenseVoiceProvider\nPCM WAV 校验 → Isolate.run\nSenseVoice INT8／sherpa_onnx FFI／CPU',575,540,525,200,'core',['C21'],tag='Android／Linux现场')
p.node('review','本人校对派生内容','转写／OCR 草稿、来源关系\n可继续手工整理或另行授权 AI\n不因采集或识别自动上传原件',1210,540,490,200,'person',['C22','C16','C26'],tag='实现')
p.edge('encrypt','capture','store','字节／媒体类型','flow',['C25','C26'])
p.edge('decodeOCR','store','ocr','授权读取原件','flow',['C26'],ports=(0,.8,.5,0),points=[(505,380),(505,490),(285,490)])
p.edge('decodeWav','store','speech','WAV 字节','flow',['C21'],ports=(.55,1,.5,0))
p.edge('textReview','speech','review','本地识别文本','flow',['C21','C22'])
p.edge('ocrReview','ocr','review','OCR 派生文本','flow',['C26'],ports=(.5,1,.2,1),points=[(285,788),(1308,788)])
p.edge('saveReview','review','vault','确认后保存关联草稿','auth',['C22','C26'],ports=(.5,0,.5,1))
p.note('model','模型安装边界','模型下载／离线导入／校验安装与删除独立于录音识别；下载模型产生网络流量，但转写不向网络发送音频。未安装模型显示真实状态。',90,820,1610,105,['C21'],'note')
p.text('limits','资源边界：单 Blob 当前上限 256MiB，内存加解密；代表性手机语音约837MiB峰值，不作为低资源设备保证。',60,945,1680,45,18,'#617284',refs=['C25','D06'])

# 07: privacy sequence
p=Page(7,'agent-privacy','Agent 隐私、单次授权与结果确认','时序视图  |  按人工敏感行标注做 Token 遮蔽；未标记文字会按预览获准内容发送')
for i,title,refs,t in [('owner','本人／Agent 页面',['C16'],'person'),('app','Controller／DraftAgent',['C17'],'app'),('privacy','本机 Privacy／工具',['C18','C20'],'core'),('provider','网络 AI Provider',['C35'],'external')]:
    p.lifeline(i,title,{'owner':220,'app':660,'privacy':1100,'provider':1560}[i],refs,t)
p.message('input',220,660,302,'1  输入文字与敏感行标注',['C16','C17'])
p.message('token',660,1100,360,'2  Tokenize；Token Map 留本机',['C18'])
p.message('preview',660,220,420,'3  显示精确外发预览与可选命令范围',['C16'])
p.message('approve',220,660,478,'4  仅允许本次；拒绝即停止',['C16'],auth=True)
p.message('request',660,1560,540,'5  HTTPS：获准文本／模型／协议；敏感行仅发 Token',['C17','C35'])
p.message('toolCall',1560,1100,600,'6a  可选工具请求：已启用的受限命令',['C20','C35'])
p.message('toolResult',1100,1560,662,'6b  无网络 Bash；只读遮蔽输入；返回有限结果',['C20','C35'])
p.message('response',1560,1100,724,'7  cards JSON → Schema／Token 校验 → 本机回填',['C18','C35'])
p.message('draft',1100,220,786,'8  显示建议；本人确认后保存 LifeCard 草稿与来源',['C19','C16'])
p.note('guard','取消／锁定与安全配置','锁定取消任务并丢弃结果；命令会话 finally 关闭。API Key 来自系统安全存储；Provider 没有仓储、原件或 VMK 入口。',60,880,1025,113,['C17','C27','C19'])
p.note('gap','已知后置缺口：Credential 录入／转换','Agent 仅保存 LifeCard；正文中的回填密码不是 Secret 字段，会进入通用预览／搜索。尚未贯通密码类型候选与转换。',1130,880,610,113,['D08','C19'],'control')

# 08: independent identities
p=Page(8,'identity-binding','独立身份、指纹核对与双钥挑战','时序视图  |  显示名称不是权限；独立渠道核对完整指纹，再验证接收者同时掌握双钥')
for i,title,x,refs,t in [('owner','Owner 身份／加密状态',230,['C10','C14'],'app'),('channel','本人手动文件／独立渠道',900,['D05'],'person'),('recipient','Recipient 自有身份',1570,['C13','C14'],'app')]: p.lifeline(i,title,x,refs,t)
p.message('public',1570,230,300,'1  .lrpublic：名称 + X25519／Ed25519 公钥',['C14','D05'])
p.message('verifyFp',900,230,370,'2  独立渠道核对并回输完整64位指纹',['C10','D05'],auth=True)
p.message('challenge',230,1570,446,'3  .lrchallenge：随机32字节，HPKE加密 + Owner签名',['C10','C15'])
p.message('verifyOwner',900,1570,522,'4  核对Owner指纹；验签并用自有X25519私钥解密',['C13','D05'],auth=True)
p.message('proof',1570,230,598,'5  .lrproof：挑战ID／双方指纹／随机值 + Recipient签名',['C13','D05'])
p.message('verifyProof',230,900,674,'6  Owner验签、匹配唯一挑战与7天期限；持久绑定并消费挑战',['C10','D05'])
p.note('ownerKey','Owner 私钥与持久状态','身份双钥／profile／recipient绑定／sequence 在 schema v5 加密 local_state 内。改显示名称或换日常密码不改变身份指纹。',60,840,530,150,['C10','C14','D05'])
p.note('recipientKey','Recipient 身份可独立备份','自有密码经 Argon2id 保护 .lridentity；RecoverableFile 写入。加密身份备份可以在另一独立目录恢复；不含 Owner VMK。',635,840,530,150,['C13','D05'])
p.note('identityLimits','本机信任边界与回退限制','切换接收入口先锁 Owner。无私钥及备份不能按名称找回；本机 sequence 不具硬件单调性，不宣称抗设备回滚。',1210,840,530,150,['C29','D05'],'control')

# 09: scope and recipient
p=Page(9,'scoped-delivery','限定范围交接与独立接收查看','数据流视图  |  真正交付的是加密快照；已交付副本不能通过之后修改授权撤回')
p.group('owner','Owner 已解锁域：每次手动授权',60,180,795,650,refs=['C11','D05'])
p.node('selection','选择接收者与本次范围','已绑定指纹；记录ID／可见级别\n历史另行选择；原件逐个勾选',90,242,735,144,'person',['C11','D05'],tag='现场')
p.node('snapshot','ReleasePreview → 范围快照','卡片摘要前80个UTF-16单元；完整正文按级别\n密码仅“含密码”交付Secret；历史要求相应级别\n核验原件归属；不展开关联卡片／回收区／来源链',90,438,735,177,refs=['C11','D05'])
p.node('package','Ed25519 签名 + HPKE Base 封装','X25519／HKDF-SHA256／AES-256-GCM\n.lrshare · 新ephemeral会话\npackageId + sequence + scopeDigest；不含 Owner VMK',90,650,735,160,'core',['C11','C15','D05'],tag='')
p.group('recipient','Recipient 自有身份／密码域',935,180,805,650,refs=['C12','C13'])
p.node('verify','接收验证后才展示','严格envelope／签名／双方指纹\npackageId去重、sequence高水位\nHPKE解密、摘要、记录／历史／原件范围',965,242,745,175,'core',['C12','D05'],tag='现场')
p.node('persist','提交加密接收状态','保存 .lrshare 密文\nOwner公钥／最高sequence／包SHA256\n先成功保存身份状态，再显示快照',965,460,745,155,'store',['C12'],tag='')
p.node('readonly','独立只读查看／再打开','自有密码解锁；再打开核对已记录包SHA256\n当前密码／修订密码默认遮挡；原件显式另存\n不打开、不克隆 Owner 数据库',965,655,745,170,refs=['C12','C13','D05'],tag='现场')
p.edge('selectScope','selection','snapshot','本人核对','auth',['C11'],ports=(.5,1,.5,0))
p.edge('seal','snapshot','package','实际选定快照','flow',['C11'],ports=(.5,1,.5,0))
p.edge('fileTransfer','package','verify','手动传递','flow',['D05','C11','C12'],ports=(1,.5,0,.55),points=[(892,730),(892,338)])
p.edge('receipt','verify','persist','拒绝错误／旧包／重复；通过才提交','flow',['C12'],ports=(.5,1,.5,0))
p.edge('view','persist','readonly','提交成功','flow',['C12'],ports=(.5,1,.5,0))
p.note('limit','工程限额与真实授权边界','最多200条；原件合计64MiB；快照128MiB／wire180MiB。当前 scopeEpoch 固定1；没有自动撤权、远程到达证明或可信离线时间锁。',60,846,1030,143,['D05','C11','C12'])
p.note('simulation','生命状态模拟独立于真实交付','Active ↔ Incapacitated；两者可到Deceased\nDeceased无恢复转换（调试重置另行处理）\n模拟／Executor View不调用真实导出服务。',1135,846,605,143,['C28','D05'],'control')

# 10: backup and supplement
p=Page(10,'backup-restore','完整／分层备份与原件补充恢复','工作流视图  |  Owner备份与接收者快照分离；数据库／附件包必须来自同一认证快照')
p.node('export','Owner 暂停数据库后导出','当前凭证认证；all便携认证用独立 R\n同次暂停：配对snapshotId + 同一Header',60,185,1680,140,refs=['C07','D05'],tag='实现／现场')
p.node('full','完整 .lvault v2 / full','Header v3 + DB + 全部加密Blob\n认证manifest；不能有 omitted',60,357,515,145,'store',['D05','C06'],tag='')
p.node('dbOnly','数据库 .lvault v2 / database','Header + DB；manifest.omitted 精确列出\n省略Blob的路径、密文字节长度、SHA256',640,357,520,145,'store',['D05','C07'],tag='')
p.node('attachments','原件 .lvault v2 / attachments','Header + 加密Blob；共享snapshotId\n仅补充包，不能单独恢复完整库',1225,357,515,145,'store',['D05','C07'],tag='')
p.node('restore','认证暂存 → 目录事务安装','核验清单／MAC／路径／规模；验证新库\nHeader v3恢复进入受限重设与全库换钥\n密码单分支或 R；异机all用 R',60,607,515,207,refs=['C06','C08','D05'],tag='现场')
p.node('missing','加密 backup.missing 状态','omitted哈希／snapshotId／旧Blob解密钥\n全部保存在SQLCipher内；重设时保留\n读取缺失原件提示；已有原件可先换钥',640,607,520,207,'core',['C06','C07','C05'],tag='现场')
p.node('supplement','补齐原件：旧钥 → 当前新 VMK','验证旧manifest MAC／相同snapshotId\n逐项核验密文长度／SHA256并解密\n用当前VMK重加密，逐项清除缺失状态',1225,607,515,207,refs=['C07','D05'],tag='现场')
p.edge('fullExport','export','full','full','flow',['C06'],ports=(.15,1,.5,0))
p.edge('dbExport','export','dbOnly','database','flow',['C07'],ports=(.5,1,.5,0))
p.edge('attExport','export','attachments','attachments','flow',['C07'],ports=(.85,1,.5,0))
p.edge('fullRestore','full','restore','恢复','flow',['C06'],ports=(.5,1,.5,0))
p.edge('dbRestore','dbOnly','missing','仅DB恢复后记录缺失','flow',['C06'],ports=(.5,1,.5,0))
p.edge('reset','restore','missing','受限重设','flow',['C06','C05'],ports=(1,.5,0,.5))
p.edge('pair','attachments','supplement','导入配对补充包','flow',['C07'],ports=(.5,1,.5,0))
p.edge('oldKey','missing','supplement','旧钥','flow',['C07'])
p.note('constraints','认证与中断约束','不同snapshotId即使内容相同也拒绝；补充失败可重试，已完成项保留。未补齐时拒绝导出新完整包／配对组；设备引用不承诺异机可用。',60,850,1090,139,['C07','D05'])
p.note('compat','兼容与资源边界','v1容器只支持Header v1；保留旧reader。\nv2支持Header v3。上限10000条目／展开2GiB；当前内存构建，大包待验。',1195,850,545,139,['D05'],'control')

# 11: key rotation and interruption states
p=Page(11,'security-recovery','独立恢复、全库换钥与中断恢复','状态／事务视图  |  会话状态与文件事务分开；受限恢复不能直接进入普通资料页面')
p.group('session','会话状态：Header v3 独立恢复路径',60,180,1680,214,refs=['C04','C05'])
p.node('locked','locked','等待日常凭证／独立R',90,240,335,110,'store',['C04'],tag='')
p.node('restricted','recovering：受限重设','R认证后只可设置全部新日常材料\n新R回输确认；普通资料投影不可达',615,235,545,122,'control',['C04','C05'],tag='')
p.node('unlocked','unlocked','新库核验提交后正常会话\n日常认证也可从locked进入',1370,235,340,122,refs=['C05'],tag='')
p.edge('rUnlock','locked','restricted','独立 R','auth',['C04'])
p.edge('resetFinish','restricted','unlocked','重设 + 全库换钥 + 提交','auth',['C05'])
p.group('transaction','VaultSecurityService／VaultBackupService → VaultRestoreTransaction（共用安装机制）',60,435,1680,360,refs=['C05','C06','C08'])
p.node('prepare','1  认证与 staging','新VMK／Header v3；导出逻辑状态\n新SQLCipher导入；重加密现有Blob\n保留ID／修订／身份／缺失状态',90,502,360,210,refs=['C05'],tag='')
p.node('intent','2  写入安装意图','关闭旧会话／清除投影\njournal → incoming\n旧库 → rollback → 新库安装',505,502,350,210,'core',['C08','C06'],tag='')
p.node('verify','3  核验新库后提交','验证打开；换钥核验现有原件\n写独立 commit marker\n提交点前失败：关闭并 recover',910,502,360,210,'core',['C05','C08'],tag='')
p.node('cleanup','4  清理与进入新会话','提交后清理旧加密目录／记录\n清理失败：保留新库与残留副本\n旧设备引用提交后清理',1325,502,385,210,refs=['C08','C05'],tag='')
p.edge('stageToIntent','prepare','intent','已准备','flow',['C05','C08'])
p.edge('installToVerify','intent','verify','已安装','flow',['C08'])
p.edge('verifyToCommit','verify','cleanup','已提交','flow',['C08'])
p.note('rollback','下次启动：先 recover，再选择创建／解锁','有旧库且未提交：核对旧Header摘要后保守回滚；有匹配commit：保留新库，不因清理失败回滚。首次恢复无旧库：保留认证暂存库并锁定，要求重新认证。异常目录／journal：进入failure，不创建空库覆盖。',60,842,1090,145,['C02','C09'])
p.note('boundaries','旧库升级与旧备份的边界','旧Header由本人主动升级，不在启动时自动迁移。\n旧VMK不能解开新数据；旧备份仍可能读旧资料。\nJournal／commit不是密码学信任锚，不含秘密。',1195,842,545,145,['D04','C05','C09'],'control')

def write_outputs():
    OUT.mkdir(parents=True,exist_ok=True)
    ET.indent(mxfile,space='  ')
    ET.ElementTree(mxfile).write(OUT/'LiveRelay-MVP0.4-system-architecture.drawio',encoding='utf-8',xml_declaration=True)
    record=dict(version='1.0',date='2026-10-04',sourceCommit='6fbee32819fdc50413f80ec8e8561c450a0b4735',documentationCommit='a586349b9b5693084d74deeac5317d5a0ae7df0b',sources=SOURCES,pages=[dict(number=p.n,title=p.title,slug=p.slug,cells=p.items) for p in PAGES])
    (OUT/'evidence-index.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
    md=['# 关键节点与连线来源索引','', '图版 v1.0；源码 `6fbee32`；文档 `a586349`；2026-10-04。原生 mxCell 的 `evidence` 属性存来源编号，cell ID 与下面一致。来源行号由生成器检查锚点后生成；版本变动时需重建。','', '## 来源目录','', '| 编号 | 来源 | 位置 |','| --- | --- | --- |']
    for k,s in SOURCES.items(): md.append(f'| {k} | {s["title"]} | [{s["path"]}:{s["line"]}](../../../{s["path"]}#L{s["line"]}) |')
    for p in PAGES:
        md += ['',f'## {p.n:02d} {p.title}','','| 原生 cell ID | 类型／关键语义 | 来源 |','| --- | --- | --- |']
        for item in p.items:
            if not item['refs']: continue
            label=__import__('re').sub('<[^>]+>',' ',item['label']).strip().replace('|','／')
            label=html.unescape(label)
            md.append(f'| `{item["id"]}` | {label} | {", ".join(item["refs"])} |')
    md += ['', '## 文档／实现差异核对','','1. 安全11（2026-10-03）末尾仍将Android真机强生物识别列为待验；安全10与10月4日实际联调证据记录小米13启用／解锁／取消／换钥／恢复已通过。本图使用后续事实，保留更多机型／新指纹／all与文件因素／正式安全复核待验边界。',
    '2. 产品范围文档（2026-10-03）的部分段落仍用“未来”描述独立恢复、任一／全部、真实本机接收身份；其自身声明不是实现状态。安全10／11与当前源码已实现本机切片，本图不把旧阶段文字当作当前未实现结论。',
    '3. 安全10说“保留加密旧副本”；`vault_restore_transaction.dart` 的正常成功路径核对旧Header摘要后删除rollback目录（install末尾），提交后清理失败与启动recover才保留残留。第11页按真实代码表达成功清理／失败保留，未修改规范或架构；后续应澄清该句的适用条件。',
    '4. Header升级与SQLCipher schema迁移不同：旧Header不在启动自动升级；数据库自身仍有Drift onUpgrade（含schema v5 local_state）。本图明确限定“Header主动升级”，不声称数据库没有迁移。',
    '5. 本机最高sequence用于拒绝重复／旧包，但身份备份回退没有硬件单调计数。图中没有宣称抗离线设备回滚或远程撤销。', '', '本次仅记录实现证据与差异，不改应用源码、稳定契约或已确认架构原则。','']
    (OUT/'evidence-index.md').write_text('\n'.join(md))
    stats=[]
    for p in PAGES:
        for item in p.items:
            for ref in item['refs']: assert ref in SOURCES,(item['id'],ref)
        cells=list(p.root)
        edges=sum(c.get('edge')=='1' for c in cells)
        vertices=sum(c.get('vertex')=='1' for c in cells)
        # Native graph integrity and one-page bounds, excluding routing labels.
        ids={c.get('id') for c in cells}
        for c in cells:
            if c.get('source'): assert c.get('source') in ids
            if c.get('target'): assert c.get('target') in ids
        for id,(x,y,w,h) in p.geoms.items(): assert x>=0 and y>=0 and x+w<=W and y+h<=H,(p.n,id)
        stats.append(dict(page=p.n,slug=p.slug,vertices=vertices,edges=edges,width=W,height=H))
    (OUT/'native-structure-check.json').write_text(json.dumps(dict(pages=stats,allNativeEditable=True,embeddedRasterCount=0),ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(dict(pages=len(PAGES),nativeVertices=sum(x['vertices'] for x in stats),nativeEdges=sum(x['edges'] for x in stats),sources=len(SOURCES),file=str(OUT/'LiveRelay-MVP0.4-system-architecture.drawio')),ensure_ascii=False))

if __name__=='__main__': write_outputs()
