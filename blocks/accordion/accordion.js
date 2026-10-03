export default async function decorate(block) {
  [...block.children].forEach((row) => {
    const label = row.children[0];
    const summary = document.createElement('summary');
    summary.className = 'accordion-item-label';
    summary.append(...label.childNodes);
    summary.setAttribute('aria-expanded', 'false');

    const body = row.children[1];
    body.className = 'accordion-item-body';

    const details = document.createElement('details');
    details.className = 'accordion-item';
    details.append(summary, body);

    row.replaceWith(details);
  });

  const items = [...block.children];

  const syncExpanded = () => {
    items.forEach((details) => {
      const summary = details.querySelector('summary');
      summary.setAttribute('aria-expanded', details.open ? 'true' : 'false');
    });
  };

  // Authored content may arrive with more than one item already open
  // (rule 1 applies to the initial state too): keep only the first one.
  const initiallyOpen = items.filter((details) => details.open);
  initiallyOpen.slice(1).forEach((details) => { details.open = false; });
  syncExpanded();

  // Exclusive-open: close every other item on a summary's own click,
  // before the browser applies that click's native open/close toggle.
  // Acting pre-toggle (rather than each item reacting to its own `toggle`
  // event afterwards) means no two items' native open state can ever
  // change within the same tick, so there is no toggle-event-ordering
  // race between items to get wrong. `aria-expanded` is re-synced on a
  // deferred callback rather than the `toggle` event itself, since the
  // browser queues `toggle` as a task and reading state immediately
  // after a click would otherwise see stale `aria-expanded` values.
  items.forEach((details) => {
    const summary = details.querySelector('summary');
    summary.addEventListener('click', () => {
      if (!details.open) {
        items.forEach((other) => {
          if (other !== details) other.open = false;
        });
      }
      setTimeout(syncExpanded, 0);
    });
  });
}
