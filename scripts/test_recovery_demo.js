const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const path = require('path');
const html = fs.readFileSync(path.join(__dirname, '../interactive/failover.html'), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const elements = new Map();
function el(id) {
  if (!elements.has(id)) elements.set(id, {
    checked: false, textContent: '', children: [],
    classList: {toggle() {}}, setAttribute() {},
    append(child) {this.children.push(child);}
  });
  return elements.get(id);
}
const document = {
  querySelector: s => el(s),
  querySelectorAll: () => [el('#fenced'), el('#rpo')],
  getElementById: id => el('#'+id),
  createElement: () => ({setAttribute() {}})
};
const context = vm.createContext({document});
vm.runInContext(script, context);
vm.runInContext('choose(3)', context);
assert.equal(vm.runInContext('selected', context), 2);
el('#fenced').checked = true;
vm.runInContext('choose(3)', context);
assert.equal(vm.runInContext('selected', context), 2);
el('#rpo').checked = true;
vm.runInContext('choose(3)', context);
assert.equal(vm.runInContext('selected', context), 3);
vm.runInContext('choose(4)', context);
assert.equal(vm.runInContext('selected', context), 4);
el('#fenced').checked = false;
el('#fenced').onchange();
assert.equal(vm.runInContext('selected', context), 2);
assert.equal(el('nav').children.length, 5);
console.log('Recovery gate logic: PASS (DOM stub, not browser visual validation)');
