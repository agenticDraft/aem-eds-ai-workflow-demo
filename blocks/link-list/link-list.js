export default async function decorate(block) {
  const ul = document.createElement('ul');
  [...block.children].forEach((row) => {
    const a = row.querySelector('a');
    if (!a) return;
    const li = document.createElement('li');
    li.append(a);
    ul.append(li);
  });
  const nav = document.createElement('nav');
  nav.setAttribute('aria-label', 'Link list');
  nav.append(ul);
  block.replaceChildren(nav);
}
