import { createOptimizedPicture } from '../../scripts/aem.js';

export default async function decorate(block) {
  block.querySelectorAll('picture > img').forEach((img) => {
    img.closest('picture').replaceWith(createOptimizedPicture(img.src, img.alt, false, [{ width: '220' }]));
  });
}
