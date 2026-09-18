import { createOptimizedPicture } from '../../scripts/aem.js';

export default async function decorate(block) {
  const row = block.firstElementChild;
  const [content, media] = [...row.children];
  content.classList.add('features-carousel-content');
  media.classList.add('features-carousel-media');

  const picture = media.querySelector('picture');
  if (picture) {
    const img = picture.querySelector('img');
    picture.replaceWith(createOptimizedPicture(img.src, img.alt, false, [{ width: '750' }]));
  }
}
