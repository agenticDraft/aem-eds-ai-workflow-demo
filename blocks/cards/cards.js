import { createOptimizedPicture } from '../../scripts/aem.js';

// This project has no real inventory data source, so stock status is
// simulated: a mock lookup, keyed on the card's own body text, evaluated
// fresh on every decoration rather than read from authored markup or fixed
// at authoring time.
function mockStockStatus(itemKey) {
  let hash = 0;
  for (let i = 0; i < itemKey.length; i += 1) hash = (hash * 31 + itemKey.charCodeAt(i)) % 100000;
  return hash % 5 === 0 ? 'out-of-stock' : 'in-stock';
}

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

    const itemKey = li.querySelector('.cards-card-body')?.textContent.trim() || '';
    const status = mockStockStatus(itemKey);
    const stock = document.createElement('p');
    stock.className = `cards-card-stock cards-card-stock-${status}`;
    stock.textContent = status === 'in-stock' ? 'In stock' : 'Out of stock';
    li.append(stock);

    ul.append(li);
  });
  ul.querySelectorAll('picture > img').forEach((img, index) => img.closest('picture').replaceWith(createOptimizedPicture(img.src, img.alt, index === 0, [{ width: '750' }])));
  block.replaceChildren(ul);
}
