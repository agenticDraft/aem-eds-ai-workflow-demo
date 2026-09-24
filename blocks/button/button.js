/**
 * Decorates a standalone button block.
 *
 * The block's own variation (e.g. `green`) is already a class on `block` by the time this runs —
 * `aem.js` reads it from the block name row (`Button (green)`) before `decorate()` is called — so
 * this function does not read or apply the variation name itself; it only turns the authored link
 * into the project's own `button` class, the same class `decorateButtons` (scripts/scripts.js)
 * already assigns to an emphasised link outside a block. It never adds a colour class: a plain
 * (no-variation) instance keeps whatever colour `styles/styles.css`'s shared `a.button` rule
 * itself supplies (none), so it must not invent one.
 * @param {HTMLElement} block The button block element
 */
export default async function decorate(block) {
  const link = block.querySelector('a[href]');
  if (!link) return;

  link.classList.add('button');
  const wrapper = link.closest('p');
  if (wrapper) wrapper.classList.add('button-wrapper');
}
