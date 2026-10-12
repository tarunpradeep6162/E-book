from pathlib import Path
import re
r=Path(__file__).resolve().parents[1]
figures={1:('01-before-after','Separate cloud ownership, workload releases, and durable data.'),4:('04-vpc','The conceptual production layout keeps the database private; the executable chapter lab is smaller.'),8:('08-jenkins-storage','Controller compute is replaceable; its verified mount and recovery copies have independent lifecycles.'),12:('01-before-after','Terraform state drives cloud provisioning, while an image digest drives a Kubernetes workload release.'),15:('15-storage-topology','An existing EBS volume stays in its zone. Cross-zone recovery creates or uses a different data copy.'),16:('16-blue-green','Green serves while Blue is updated and verified; traffic switches only after the release gate.'),20:('20-cross-cloud','The tunnel, return route, DNS, and identity checks all participate in a working transaction.'),21:('21-failover','Fence the old writer, approve the recovery point, promote, then route and verify.')}
tips={1:'Keep application, infrastructure, configuration, and persistent data under explicit lifecycle ownership.',2:'Commit the provider lock file and review upgrades as changes to the execution toolchain.',3:'Give state writers permission to delete only their own lock, not their state object.',4:'Test a successful SSM session and a denied unsolicited inbound connection.',5:'Use stable module keys for identity and separate roots for different trust boundaries.',6:'Promote the tested registry digest without rebuilding for each environment.',7:'Prove data survives container replacement and a separate backup restoration.',8:'Require the real EBS mount before starting Jenkins; an empty directory is not persistence.',9:'Keep production credentials and release agents away from untrusted pull-request execution.',10:'Bind the published digest to the tested image and preserve its evidence record.',11:'Apply the saved approved plan; stale assumptions require a new review.',12:'Use controllers, accurate readiness, and schedulable capacity to replace failed workloads.',13:'Record module, provider, add-on, identity, and node-image versions together.',14:'Test allowed and denied paths on a network implementation that enforces NetworkPolicy.',15:'Treat volume topology, database promotion, and schema recovery as separate mechanisms.',16:'Preserve schema compatibility while old and new application versions coexist.',17:'Bound replica count and connection pools against measured database capacity.',18:'Test the Azure recovery control path while primary-cloud dependencies are unavailable.',19:'Test provider-specific failure semantics at narrow application adapter boundaries.',20:'Verify both peers, both route directions, and private DNS from the actual caller.',21:'Record positive fencing evidence before approving a second writer.',22:'Give every experiment an independent stop mechanism and prove ordinary controls return afterward.'}
progress={
4:('hcl','resource "aws_vpc" "lab" {\n  cidr_block = "10.40.0.0/16"\n  enable_dns_support = true\n  enable_dns_hostnames = true\n}', 'This defines the address domain. It does not create subnets, routing, or a safe administrative path. The complete files below add those responsibilities.'),
6:('dockerfile','ARG PYTHON_BASE\nFROM ${PYTHON_BASE}\nWORKDIR /app\nCOPY app.py /app/app.py\nCMD ["python", "/app/app.py"]','This shows the packaging contract only. The complete Dockerfile below adds build separation, a non-root identity, and explicit runtime behavior.'),
10:('groovy',"stage('Test') {\n  steps {\n    sh 'python3 -m unittest discover -s tests'\n  }\n}",'Start with test execution. This excerpt is not the release gate: the complete pipeline additionally rejects zero tests, tests the image, scans it, and records the ECR digest.'),
11:('bash','terraform init -lockfile=readonly\nterraform validate\nterraform plan -out=tfplan\nterraform show tfplan\n# Review before applying this exact file.','These commands establish the plan artifact. The complete Jenkins workflow below adds protected storage, approval, identity checks, and serialization.'),
12:('yaml','apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: orders-api\nspec:\n  replicas: 2','This is the controller intent, not a deployable manifest. The complete Deployment below adds selectors, the Pod template, probes, resource budgets, and security settings.'),
13:('hcl','module "eks" {\n  source  = "terraform-aws-modules/eks/aws"\n  version = "21.3.0"\n  name    = "orders-platform"\n}','The module call identifies implementation and ownership. The complete configuration below supplies network placement, version selection, access, and capacity.'),
15:('yaml','apiVersion: storage.k8s.io/v1\nkind: StorageClass\nmetadata:\n  name: orders-ebs-gp3\nprovisioner: ebs.csi.aws.com','This identifies the storage provisioner. The complete class below adds topology-aware binding, encryption, expansion, and retention policy.'),
18:('hcl','resource "azurerm_resource_group" "platform" {\n  name     = "orders-platform-lab"\n  location = "centralindia"\n}','Begin with Azure resource ownership. The full AKS configuration below adds the subscription context, network, cluster identity, private endpoint, and workload federation.'),
19:('hcl','resource "google_compute_network" "platform" {\n  name                    = "orders-platform"\n  auto_create_subnetworks = false\n}','Begin with an explicit network instead of automatic subnet creation. The complete root below adds reviewed ranges, cluster placement, and upgrade policy.')}
for p in sorted((r/'chapters').glob('*.md')):
 n=int(p.name[:2]);s=p.read_text()
 if n==0 or '::: {.callout .failure}' in s:continue
 # Wrap the initial failure story; keep lengthy analysis outside the short card.
 m=re.search(r'(^## .*?\n.*?)(?=^## |\Z)',s,re.M|re.S)
 if m:s=s[:m.start()]+'::: {.callout .failure}\n'+m.group(1).rstrip()+'\n:::\n\n'+s[m.end():]
 if n in figures:
  name,caption=figures[n];insert=f'## Architecture at a Glance\n\n![{caption}](images/{name}.svg){{width=100%}}\n\n'
  if n==21:insert+='Explore the five recovery states in the [interactive companion](https://github.com/tarunpradeep6162/E-book/blob/main/interactive/failover.html). Download the file and open it in a browser; it performs no cloud operations.\n\n'
  end=s.index(':::',s.index(':::')+3)+3;s=s[:end]+'\n\n'+insert+s[end:]
 if n==1:
  s=s.replace('The API persists orders and work records in a database transaction; the worker claims pending work and processes it with idempotent handlers.','The API commits orders and work records; idempotent workers process pending work.')
  pos=s.index('## Four Lifecycles')
  s=s[:pos]+'The public companion repository contains the exact code examples.\n\n```bash\ngit clone https://github.com/tarunpradeep6162/E-book.git\ncd E-book/examples\n```\n\n'+s[pos:]
 if n==6:
  pos=s.index('## Define the Application Contract');s=s[:pos]+'A Docker image is like a standardized shipping container: a consistent package travels between compatible hosts. The analogy stops at compatibility; CPU architecture, kernel capabilities, credentials, and external data still need explicit contracts.\n\n'+s[pos:]
 if n==12:
  pos=s.index('## Deployments Own');s=s[:pos]+'Think of a Deployment controller as a restaurant manager replacing a missing waiter. The manager still needs a trained replacement and available space. Kubernetes likewise needs a pullable image, valid configuration, and node capacity; it cannot replace missing database records.\n\n'+s[pos:]
 if n in progress:
  lang,code,why=progress[n];pos=s.find('### ')
  if pos!=-1:s=s[:pos]+f'### First, Read the Smallest Contract\n\n```{lang}\n{code}\n```\n\n{why}\n\n'+s[pos:]
 # Box existing takeaway content without a duplicate internal heading.
 s=re.sub(r'^## Key Takeaways\n(.*?)(?=^## |\Z)',lambda m:'::: {.callout .takeaways}\n'+m.group(1).strip()+'\n:::\n\n',s,flags=re.M|re.S)
 if n!=1:
  anchor=s.find('::: {.callout .takeaways}')
  if anchor==-1:anchor=len(s)
  s=s[:anchor]+f'::: {{.callout .protip}}\n{tips[n]}\n:::\n\n'+s[anchor:]
 p.write_text(s)
print('Added visual callouts, eight chapter figures, analogies, and staged code-reading introductions')
