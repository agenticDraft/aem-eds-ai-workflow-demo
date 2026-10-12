import { createOptimizedPicture } from '../../scripts/aem.js';

export default async function decorate(block) {
  const ul = document.createElement('ul');
  [...block.children].forEach((row) => {
    const li = document.createElement('li');
    [...row.children].forEach((cell) => li.append(...cell.childNodes));
    ul.append(li);
  });
  ul.querySelectorAll('picture > img').forEach((img) => img.closest('picture').replaceWith(createOptimizedPicture(img.src, img.alt, false, [{ width: '320' }])));
  block.replaceChildren(ul);
}
