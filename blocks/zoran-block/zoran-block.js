/**
 * Decorates the zoran-block callout: wraps the block's authored text in a
 * single element carrying a dedicated class so it can be styled distinctly
 * from the rest of the block, and adds a Dismiss control that hides the
 * callout for the current page view only.
 * @param {Element} block The zoran-block element
 */
export default async function decorate(block) {
  const text = block.textContent.trim();
  const wrapper = document.createElement('p');
  wrapper.className = 'zoran-block-callout';
  wrapper.textContent = text;

  const dismiss = document.createElement('button');
  dismiss.type = 'button';
  dismiss.className = 'zoran-block-dismiss';
  dismiss.textContent = 'Dismiss';
  dismiss.addEventListener('click', () => {
    wrapper.hidden = true;
  });

  block.replaceChildren(wrapper, dismiss);
}
