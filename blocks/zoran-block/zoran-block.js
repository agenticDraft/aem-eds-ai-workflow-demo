/**
 * Decorates the zoran-block callout: wraps the block's authored text in a
 * single element carrying a dedicated class so it can be styled distinctly
 * from the rest of the block.
 * @param {Element} block The zoran-block element
 */
export default async function decorate(block) {
  const text = block.textContent.trim();
  const wrapper = document.createElement('p');
  wrapper.className = 'zoran-block-callout';
  wrapper.textContent = text;
  block.replaceChildren(wrapper);
}
