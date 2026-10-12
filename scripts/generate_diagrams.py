from pathlib import Path
from reportlab.graphics.shapes import Drawing, Rect, String, Line, Polygon, PolyLine, Ellipse
from reportlab.graphics import renderPDF, renderSVG
from reportlab.lib.colors import HexColor, Color
R=Path(__file__).resolve().parents[1]/'images';R.mkdir(exist_ok=True)
P='#5E35B1';INK='#1E293B';MUTED='#475569';BORDER='#CBD5E1';GREEN='#047857';RED='#B91C1C'
def start(title,subtitle,h=540):
 d=Drawing(960,h);d.add(Rect(0,0,960,h,fillColor=HexColor('#FFFFFF'),strokeColor=None));txt(d,24,h-42,title,25,P,True);txt(d,24,h-70,subtitle,13,MUTED);return d
def txt(d,x,y,s,size=15,c=INK,bold=False):d.add(String(x,y,s,fontName='Helvetica-Bold' if bold else 'Helvetica',fontSize=size,fillColor=HexColor(c)))
def box(d,x,y,w,h,label,sub='',color='#F8FAFC',stroke=BORDER):
 d.add(Rect(x,y,w,h,rx=10,ry=10,fillColor=HexColor(color),strokeColor=HexColor(stroke),strokeWidth=1.5));txt(d,x+16,y+h-28,label,16,INK,True)
 if any(word in label.lower() for word in ('database', 'postgresql', 'ebs')):
  cx=x+w-30;cy=y+h-28
  d.add(Rect(cx-10,cy-13,20,24,fillColor=HexColor('#FFFFFF'),strokeColor=HexColor(P)))
  d.add(Ellipse(cx,cy+11,10,4,fillColor=HexColor('#EDE9FE'),strokeColor=HexColor(P)))
  d.add(Ellipse(cx,cy-13,10,4,fillColor=HexColor('#FFFFFF'),strokeColor=HexColor(P)))
 if sub:
  for j,s in enumerate(sub.split('|')):txt(d,x+16,y+h-52-j*20,s,13,MUTED)
def arrow(d,x1,y1,x2,y2,label='',color=P,dash=False):
 l=Line(x1,y1,x2,y2,strokeColor=HexColor(color),strokeWidth=2)
 if dash:l.strokeDashArray=[5,4]
 d.add(l)
 import math
 a=math.atan2(y2-y1,x2-x1);z=9
 pts=[x2,y2,x2-z*math.cos(a-.4),y2-z*math.sin(a-.4),x2-z*math.cos(a+.4),y2-z*math.sin(a+.4)]
 d.add(Polygon(pts,fillColor=HexColor(color),strokeColor=None))
 if label:txt(d,(x1+x2)/2+8,(y1+y2)/2+10,label,12,color)
def save(d,name):
 renderPDF.drawToFile(d,str(R/(name+'.pdf')))
 renderSVG.drawToFile(d,str(R/(name+'.svg')))
 import re
 p=R/(name+'.svg');p.write_text(re.sub(r'<!DOCTYPE[^>]*>', '', p.read_text(), flags=re.S))
# Before and after: state flows to Terraform, never directly to a Pod.
d=start('From snowflake to declared platform','Configuration, artifacts, and durable data have separate owners.',600)
box(d,24,80,420,400,'BEFORE: one undocumented host','Mutable packages + application + database',color='#FFF1F2',stroke='#FDA4AF')
for x,y,label in [(44,350,'Console edits'),(230,350,'Local secrets'),(60,240,'Unknown release'),(235,140,'Database files')]:box(d,x,y,180,70,label)
for a in [(134,350,325,210),(320,350,145,310),(145,240,325,210),(325,140,130,350)]:arrow(d,*a,color=RED)
box(d,492,80,444,400,'AFTER: explicit ownership')
box(d,514,348,180,70,'Terraform + state','Cloud resource ownership')
box(d,718,348,194,70,'Image digest','Workload release input')
box(d,530,215,366,92,'Kubernetes cluster','Controllers replace Pods; policies govern traffic')
box(d,530,110,366,65,'Durable database','Backups and recovery are independent')
arrow(d,604,348,604,307,'Provision');arrow(d,810,348,810,307,'Deploy');arrow(d,710,215,710,175,'Transactions')
save(d,'01-before-after')
d=start('VPC: placement, routing, and permitted callers','Public/private labels do not replace application authorization.')
box(d,24,45,912,390,'AWS VPC 10.40.0.0/16')
box(d,48,80,408,295,'Public subnet 10.40.0.0/24','Route to Internet Gateway',color='#EFF6FF')
box(d,504,80,408,295,'Private subnet 10.40.10.0/24','No direct Internet Gateway route',color='#ECFDF5')
box(d,75,240,350,78,'Load balancer','Public entry point: reviewed TLS')
box(d,75,125,350,78,'NAT gateway','Outbound path, not an inbound firewall')
box(d,530,240,350,78,'Application instances','No public IP; SSM administration')
box(d,530,125,350,78,'PostgreSQL database','Only authorized application connections')
arrow(d,425,280,530,280,'HTTPS');arrow(d,710,240,710,203,'5432');arrow(d,530,145,425,145,'Outbound')
txt(d,40,20,'Conceptual production component view; Chapter 4 executable lab provisions a private SSM instance.',12,MUTED)
save(d,'04-vpc')
d=start('Jenkins: replace compute, retain its home','A persistent mount is necessary; independent backup is still required.',500)
box(d,30,210,390,195,'Disposable EC2 instance','Docker runs Jenkins|No builds on the controller')
box(d,65,245,320,70,'/var/jenkins_home','Bind mount, not container writable layer')
box(d,500,240,420,130,'Retained encrypted EBS','Filesystem UUID mounted at /srv/jenkins|Same-AZ attachment; verified ownership')
arrow(d,385,280,500,280,'Mount')
box(d,500,80,420,100,'Protected snapshot / backup','Restore into another AZ when needed')
arrow(d,710,240,710,180,'Quiesce and back up')
txt(d,30,80,'Fail closed if the intended mount is missing.',17,RED,True)
save(d,'08-jenkins-storage')
d=start('Stateful Kubernetes: a volume has a zone','WaitForFirstConsumer chooses compatible placement; it does not move existing EBS.')
box(d,30,100,410,320,'Availability Zone A')
box(d,60,275,350,80,'StatefulSet Pod postgres-0','Scheduled on compatible node')
box(d,60,135,350,85,'PVC -> PV -> EBS','Volume remains in AZ A')
arrow(d,230,275,230,220,'Mount')
box(d,520,100,410,320,'Availability Zone B')
box(d,550,275,350,80,'Replacement Pod','Cannot attach AZ A volume here',color='#FFF1F2',stroke=RED)
box(d,550,135,350,85,'Recovery path','Replication or snapshot -> new volume')
arrow(d,410,180,550,180,'Restore, not attach',dash=True)
save(d,'15-storage-topology')
d=start('Blue-green release: build, verify, then switch','Traffic colors describe deployment versions, not database write ownership.',430)
for x,title,a,b in [(30,'1. Green serves','Green: current traffic','Blue: not receiving users'),(340,'2. Blue is verified','Green: still serving','Blue: tests + readiness'),(650,'3. Traffic moves','Blue: approved release','Green: drain / rollback window')]:
 box(d,x,100,280,240,title);box(d,x+15,215,250,62,a,color='#EFF6FF' if x==650 else '#ECFDF5');box(d,x+15,130,250,62,b,color='#ECFDF5' if x==650 else '#EFF6FF')
arrow(d,310,220,340,220);arrow(d,620,220,650,220)
txt(d,30,55,'Schema compatibility and in-flight work must remain safe across both versions.',15,RED)
save(d,'16-blue-green')
d=start('Cross-cloud connectivity: both directions matter','Distinct CIDRs, private DNS, scoped identities, and measured replication paths.')
box(d,30,160,350,230,'AWS VPC 10.50.0.0/16','Application + primary data|Independent state backend')
box(d,580,160,350,230,'Azure VNet 10.80.0.0/16','Recovery application + standby|Independent state backend')
box(d,400,235,160,95,'VPN / inspection','Both peers configured')
arrow(d,380,300,400,300);arrow(d,560,300,580,300);arrow(d,580,255,560,255,color=GREEN);arrow(d,400,255,380,255,color=GREEN)
box(d,180,40,600,90,'Private DNS and recovery identity','DNS forwarding is separate from the tunnel; no primary-only control dependency.')
txt(d,40,125,'Observe latency, MTU, packet loss, egress cost, and standby catch-up.',15,MUTED)
save(d,'20-cross-cloud')
d=start('Active-passive recovery: promotion follows fencing','Self-managed PostgreSQL standby; asynchronous replication and explicit approvals.',610)
steps=[('1. Normal','AWS owns writes|Azure replays standby WAL'),('2. Outage / stop','Do not assume primary is fenced|Assess lag; stop unsafe writes'),('3. Fence','Confirm old writer cannot resume|Approve accepted recovery gap'),('4. Promote','Azure becomes the only writer|Verify durable synthetic write'),('5. Route + verify','Shift DNS; account for caches|Verify API + worker; measure RPO/RTO')]
for i,(title,sub) in enumerate(steps):
 row=i//3;col=i%3;x=30+col*310;y=310 if row==0 else 90
 box(d,x,y,280,160,title,sub,color='#FFF1F2' if i==1 else '#F8FAFC')
 if col<2 and i<4:arrow(d,x+280,y+80,x+310,y+80)
arrow(d,790,310,170,250,'Decision gate',dash=True)
txt(d,30,40,'Book targets: RPO <= 5 minutes; RTO <= 60 minutes. Targets require measured evidence.',14,RED,True)
save(d,'21-failover')
print('Generated seven editable SVG diagrams and vector PDF counterparts')
