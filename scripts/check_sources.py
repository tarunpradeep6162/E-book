from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
for p in sorted((root/'chapters').glob('*.md')):
 s=p.read_text()
 assert len(re.findall(r'^```',s,re.M))%2==0, f'Unbalanced fences: {p}'
 assert 'sandbox:' not in s and 'genui' not in s, f'Export-internal link: {p}'
# Guarantee chapter examples match downloadable configuration exactly.
s=(root/'chapters/02-terraform-without-guesswork.md').read_text()
blocks=re.findall(r'```hcl\n(.*?)```',s,re.S)
for name,body in zip(['providers.tf','variables.tf','main.tf','terraform.tfvars.example'],blocks):
 assert (root/'examples/terraform-foundation'/name).read_text()==body, name
print('Source fences and chapter/example consistency: PASS')

chapters=sorted(p for p in (root/'chapters').glob('*.md') if not p.name.startswith('00-'))
assert len(chapters)==22, 'Expected exactly 22 chapters'
for p in chapters:
 count=len(p.read_text().split())
 assert 1500<=count<=2000, f'{p.name}: {count} words'
 if not p.name.startswith(('01-','02-')):
  assert '## Key Takeaways' in p.read_text(), p.name
print('22 chapters, length bounds, and takeaway sections: PASS')
