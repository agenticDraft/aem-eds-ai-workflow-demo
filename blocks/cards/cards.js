import { createOptimizedPicture } from '../../scripts/aem.js';

export default async function decorate(block) {
  /* change to ul, li */
  const ul = document.createElement('ul');
  [...block.children].forEach((row) => {
    const li = document.createElement('li');
    while (row.firstElementChild) li.append(row.firstElementChild);
    [...li.children].forEach((div) => {
      if (div.children.length === 1 && div.querySelector('picture')) div.className = 'cards-card-image';
      else div.className = 'cards-card-body';
    });
    ul.append(li);
  });
  ul.querySelectorAll('picture > img').forEach((img, index) => img.closest('picture').replaceWith(createOptimizedPicture(img.src, img.alt, index === 0, [{ width: '750' }])));
  /* an authored card button (project's own button convention) opens its link in a new tab */
  ul.querySelectorAll('.cards-card-body a.button').forEach((a) => {
    a.target = '_blank';
    a.rel = 'noopener';
  });
  block.replaceChildren(ul);
}
